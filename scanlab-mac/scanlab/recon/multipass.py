"""Flip-and-align: combine several passes of the same part (PRD FR-27.5, M9.11).

A single pass never sees the face resting on the table. The user scans the part, turns it over and
scans again; each pass is prepared on its own table, then pass i is registered onto pass 0 and all
frames are expressed in pass 0's table frame. The underside is then observed, not guessed.

Registration = several global hypotheses (FPFH + RANSAC, plus 24 axis-aligned × 12 yaw
orientations about the centroids), each refined with coarse-to-fine point-to-plane ICP, ranked by
overlap minus a physical-consistency penalty: aligned points must not sit where the other pass's
cameras saw empty space. That penalty is what rejects a plausible-looking but wrong flip of an
almost symmetric part.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, replace

import numpy as np
import open3d as o3d
import trimesh

from .capture import DepthFrame
from .pipeline import FreeSpace, Scene


_DEBUG = False


@dataclass
class Registration:
    transform: np.ndarray       # 4×4, mm, source table frame → target table frame
    fitness: float              # share of source points with a target neighbour within the final threshold
    rmse_mm: float
    free_space_violation: float
    score: float
    runner_up_score: float      # best clearly different hypothesis; close to `score` = ambiguous
    hypotheses: int

    @property
    def ambiguous(self) -> bool:
        return self.score - self.runner_up_score < 0.03

    def report(self) -> dict:
        return {"fitness": round(self.fitness, 4), "rmse_mm": round(self.rmse_mm, 4),
                "free_space_violation": round(self.free_space_violation, 4), "score": round(self.score, 4),
                "runner_up_score": round(self.runner_up_score, 4), "ambiguous": self.ambiguous,
                "hypotheses": self.hypotheses, "transform": np.round(self.transform, 6).tolist()}


def part_points(scene: Scene, frames: list[DepthFrame] | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Part points (mm, table frame) and the camera centre (mm) that saw each one."""
    pts, cams = [], []
    for f in frames if frames is not None else scene.train:
        p, _ = f.points(2, part_only=True)
        pts.append(scene.to_table_mm(p))
        cams.append(np.repeat(scene.to_table_mm(f.camera_center[None]), len(p), axis=0))
    return np.vstack(pts), np.vstack(cams)


def _cloud(points: np.ndarray, cams: np.ndarray, voxel: float) -> o3d.geometry.PointCloud:
    keys = np.floor(points / voxel).astype(np.int64)
    _, idx = np.unique(keys, axis=0, return_index=True)
    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(points[idx]))
    pcd.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=3 * voxel, max_nn=60))
    n = np.asarray(pcd.normals)
    flip = np.einsum("ij,ij->i", n, cams[idx] - points[idx]) < 0
    n[flip] *= -1
    pcd.normals = o3d.utility.Vector3dVector(n)
    return pcd


def icp_normal_aware(src_pts: np.ndarray, src_n: np.ndarray, dst_pts: np.ndarray, dst_n: np.ndarray,
                     t: np.ndarray, distances: tuple[float, ...], min_normal_dot: float = 0.7,
                     iterations: int = 30, lock_z: bool = False) -> tuple[np.ndarray, float, float]:
    """Point-to-plane ICP that only pairs surfaces facing the same way.

    Plain ICP happily matches the top of a thin plate in one pass with its bottom in the other
    (they are one plate-thickness apart): a 5 mm bracket base registered 5 mm off. Rejecting pairs
    whose normals disagree removes that false minimum. Returns (transform, fitness, rmse) at the
    last distance.
    """
    from scipy.spatial import cKDTree

    tree = cKDTree(dst_pts)
    t = t.copy()
    fitness, rmse = 0.0, np.inf
    for dist in distances:
        for _ in range(iterations):
            p = src_pts @ t[:3, :3].T + t[:3, 3]
            n = src_n @ t[:3, :3].T
            d, idx = tree.query(p, distance_upper_bound=dist)
            ok = np.isfinite(d)
            ok[ok] &= np.einsum("ij,ij->i", n[ok], dst_n[idx[ok]]) > min_normal_dot
            if ok.sum() < 6:
                break
            ps, q, nq = p[ok], dst_pts[idx[ok]], dst_n[idx[ok]]
            # Linearised point-to-plane: minimise Σ ((R p + t − q) · n)² for small rotation ω.
            a = np.c_[np.cross(ps, nq), nq]
            b = np.einsum("ij,ij->i", q - ps, nq)
            if lock_z:  # height already fixed by physics; solve the other five parameters
                x5, *_ = np.linalg.lstsq(a[:, :5], b, rcond=None)
                x = np.r_[x5, 0.0]
            else:
                x, *_ = np.linalg.lstsq(a, b, rcond=None)
            step = trimesh.transformations.euler_matrix(*x[:3], "sxyz")
            step[:3, 3] = x[3:]
            t = step @ t
            if np.linalg.norm(x) < 1e-7:
                break
        fitness = float(ok.mean())
        rmse = float(np.sqrt(np.mean(d[ok] ** 2))) if ok.any() else np.inf
    return t, fitness, rmse


def _axis_rotations() -> list[np.ndarray]:
    mats = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            m = np.zeros((3, 3))
            for row, (col, sign) in enumerate(zip(perm, signs)):
                m[row, col] = sign
            if np.linalg.det(m) > 0:
                mats.append(m)
    return mats  # the 24 proper rotations of a cube


def turned_over(t: np.ndarray, max_up_dot: float = 0.5) -> bool:
    """The source pass's 'up' ends up at least ~60° away from the target's 'up'."""
    return float(t[2, 2]) < max_up_dot


def register(source: Scene, target: Scene, seeds: int = 4, yaw_steps: int = 12,
             expect_turned: bool = True) -> Registration:
    """`expect_turned`: the second pass is the part turned over (or onto its side). For parts that look
    the same upside down (a plate), "not turned" fits the points just as well but would put the newly
    seen underside on top of the already seen top — so such hypotheses are discarded."""
    vox = max(2 * source.config.voxel_mm, 0.5)
    src_pts, src_cams = part_points(source)
    dst_pts, dst_cams = part_points(target)
    src = _cloud(src_pts, src_cams, vox)
    dst = _cloud(dst_pts, dst_cams, vox)
    reg = o3d.pipelines.registration
    feature = o3d.geometry.KDTreeSearchParamHybrid(radius=5 * vox, max_nn=100)
    f_src = reg.compute_fpfh_feature(src, feature)
    f_dst = reg.compute_fpfh_feature(dst, feature)

    c_src = np.asarray(src.points).mean(axis=0)
    c_dst = np.asarray(dst.points).mean(axis=0)
    inits = []
    for seed in range(seeds):
        o3d.utility.random.seed(seed)
        r = reg.registration_ransac_based_on_feature_matching(
            src, dst, f_src, f_dst, True, 1.5 * vox, reg.TransformationEstimationPointToPoint(False), 3,
            [reg.CorrespondenceCheckerBasedOnEdgeLength(0.9), reg.CorrespondenceCheckerBasedOnDistance(1.5 * vox)],
            reg.RANSACConvergenceCriteria(200_000, 0.999))
        inits.append(r.transformation)
    for rot in _axis_rotations():
        for k in range(yaw_steps):
            yaw = trimesh.transformations.rotation_matrix(2 * np.pi * k / yaw_steps, [0, 0, 1])[:3, :3]
            t = np.eye(4)
            t[:3, :3] = yaw @ rot
            t[:3, 3] = c_dst - t[:3, :3] @ c_src
            inits.append(t)

    # Coarse ICP on every hypothesis, ranked by overlap minus physical inconsistency (cheap on a
    # subsample); overlap alone lets symmetric wrong flips crowd out the right one.
    space = FreeSpace(target)
    slack = 3 * target.config.tau_mm
    probe = np.asarray(src.points)[:: max(1, len(src.points) // 300)]
    coarse = []
    for t in inits:
        r = reg.registration_icp(src, dst, 4 * vox, t, reg.TransformationEstimationPointToPlane(),
                                 reg.ICPConvergenceCriteria(max_iteration=20))
        penalty = space.rate(trimesh.transform_points(probe, r.transformation), slack)
        coarse.append((r.fitness - 2.0 * penalty, r.transformation))
    coarse.sort(key=lambda x: -x[0])
    not_turned = [c for c in coarse if not turned_over(c[1])]
    if expect_turned:
        coarse = [c for c in coarse if turned_over(c[1])]
        if not coarse:
            raise ValueError("no turned-over alignment found: was the part really turned between the passes?")
    back_space = FreeSpace(source)
    dst_probe = np.asarray(dst.points)[:: max(1, len(dst.points) // 3000)]
    src_probe = np.asarray(src.points)[:: max(1, len(src.points) // 3000)]

    def violation(t: np.ndarray) -> float:
        """Symmetric: source points in the target's free space and target points in the source's."""
        forward = space.rate(trimesh.transform_points(src_probe, t), slack)
        backward = back_space.rate(trimesh.transform_points(dst_probe, np.linalg.inv(t)), slack)
        return (forward + backward) / 2

    sp, sn = np.asarray(src.points), np.asarray(src.normals)
    dp, dn = np.asarray(dst.points), np.asarray(dst.normals)
    def refine(t: np.ndarray, use_contact: bool) -> tuple:
        t, fit, rmse = icp_normal_aware(sp, sn, dp, dn, t, (2 * vox, vox, 0.5 * vox))
        contact = contact_offset(t, sp, sn) if use_contact else None
        z_icp = t[2, 3]
        before = t[2, 3]
        t = _settle_along_table_normal(t, violation, vox, contact_dz=contact)
        z_settled = t[2, 3]
        by_contact = contact is not None and abs((z_settled - before) - contact) < 1e-9
        # Keep a height fixed by physical contact: where the passes share only vertical walls (an
        # overturned open box) plain ICP drifted it 1.6 mm off. Without contact (a curved underside)
        # the free-space search is only a starting point and ICP must stay free to correct it.
        t, fit, rmse = icp_normal_aware(sp, sn, dp, dn, t, (vox, 0.5 * vox), lock_z=by_contact)
        if _DEBUG:
            print(f"  [reg] z icp {z_icp:.3f} settled {z_settled:.3f} refined {t[2, 3]:.3f}")
        v = violation(t)
        if _DEBUG:
            print(f"  [reg] up·up {t[2, 2]:+.3f} contact {contact} fit {fit:.3f} viol {v:.4f}")
        return fit - 2.0 * v, fit, rmse, v, t

    finalists = [f for f in (refine(t, expect_turned) for _, t in coarse[:12])
                 if not expect_turned or turned_over(f[4])]
    if not finalists:
        raise ValueError("no turned-over alignment found: was the part really turned between the passes?")
    finalists.sort(key=lambda x: -x[0])
    best = finalists[0]
    if expect_turned and not_turned:
        # A pass that was not actually turned still yields "turned" hypotheses (24 axis guesses);
        # merging such a wrong one would silently corrupt the result. Compare with the best upright fit.
        # Only an upright fit that is also physically consistent counts: for a part that really was
        # turned, the best upright fit pokes through observed free space (bracket 24 %, handle 9 %);
        # for a part scanned twice the same way up it does not (0.5 %).
        upright = max((refine(t, False) for _, t in not_turned[:3]), key=lambda f: f[0])
        if upright[3] < 0.03 and upright[1] > best[1] + 0.15:
            raise ValueError(f"the second pass fits much better without turning the part (overlap "
                             f"{upright[1]:.2f} vs {best[1]:.2f}): either it was not turned over, or it looks "
                             f"the same both ways up and cannot be aligned reliably")

    def differs(t: np.ndarray) -> bool:
        moved_a = trimesh.transform_points(np.asarray(src.points)[::20], best[4])
        moved_b = trimesh.transform_points(np.asarray(src.points)[::20], t)
        return float(np.median(np.linalg.norm(moved_a - moved_b, axis=1))) > 3 * vox

    runner = max((f[0] for f in finalists[1:] if differs(f[4])), default=-1.0)
    return Registration(best[4], best[1], best[2], best[3], best[0], runner, len(inits))


def contact_offset(t: np.ndarray, src_pts: np.ndarray, src_n: np.ndarray, min_points: int = 200) -> float | None:
    """Height correction from physics: in the target pass the part rested on the table (z = 0), and a
    turned-over source pass sees that resting face. After alignment its flat, downward-facing points
    must lie on z = 0. Uses their median (not the lowest points, which noise pushes ~2σ too low)."""
    p = src_pts @ t[:3, :3].T + t[:3, 3]
    n = src_n @ t[:3, :3].T
    down = n[:, 2] < -0.9
    if down.sum() < min_points:
        return None
    z = p[down, 2]
    low = z[z <= np.percentile(z, 1) + 5.0]
    if len(low) < min_points:
        return None
    # Locate the face by the histogram peak, then take a median in a window *symmetric* about it:
    # a one-sided cut (lowest points + band) clips the noise asymmetrically and biased this by ~0.7 mm.
    hist, edges = np.histogram(low, bins=max(10, int((low.max() - low.min()) / 0.2)))
    peak = 0.5 * (edges[hist.argmax()] + edges[hist.argmax() + 1])
    window = low[np.abs(low - peak) <= 2.5]
    for _ in range(3):  # re-centre on the median
        centre = float(np.median(window))
        window = low[np.abs(low - centre) <= 2.5]
    return None if len(window) < min_points else -float(np.median(window))


def _settle_along_table_normal(t: np.ndarray, violation, vox: float, span_mm: float = 6.0,
                               contact_dz: float | None = None) -> np.ndarray:
    """ICP cannot pin the height when the passes share mostly vertical walls (sliding along them costs
    nothing). Free space can: too high and the part pokes through what one pass saw as empty, too
    low and it does so for the other. Line-search the table-normal offset; when the violation
    landscape is flat, prefer the physical contact height.

    Physics first: some parts (an open box turned over) share only vertical walls between passes and
    free space barely constrains their height, so the contact height is used unless it *clearly*
    raises the violation (by more than 0.03: on an overturned open box the measure is nearly blind
    along the table normal and its noise rejected a correct contact height, leaving a 1.7 mm error)."""
    def shifted(dz: float) -> np.ndarray:
        s = t.copy()
        s[2, 3] += dz
        return s

    if contact_dz is not None and abs(contact_dz) <= span_mm:
        grid = np.arange(-span_mm, span_mm + 1e-9, vox / 2)
        best = min(violation(shifted(dz)) for dz in grid)
        if violation(shifted(contact_dz)) <= best + 0.03:
            return shifted(contact_dz)

    coarse = np.arange(-span_mm, span_mm + 1e-9, vox / 2)
    scores = [violation(shifted(dz)) for dz in coarse]
    best = float(coarse[int(np.argmin(scores))])
    fine = np.arange(best - vox / 2, best + vox / 2 + 1e-9, vox / 10)
    scores = [violation(shifted(dz)) for dz in fine]
    # Many offsets may tie at zero violation; take the middle of the best plateau.
    low = min(scores)
    plateau = fine[np.asarray(scores) <= low + 1e-4]
    return shifted(float(plateau.mean()))


def merge(scenes: list[Scene], transforms: list[np.ndarray]) -> Scene:
    """Expresses every pass in pass 0's table frame (meters for poses, mm for points)."""
    ref = scenes[0]
    train, holdout, train_pass, holdout_pass = [], [], [], []
    for index, (scene, t_mm) in enumerate(zip(scenes, transforms)):
        t_m = t_mm.copy()
        t_m[:3, 3] /= 1000.0
        to_ref = t_m @ scene.world_to_table  # pass world (m) → reference table (m)
        for bucket, tags, frames in ((train, train_pass, scene.train), (holdout, holdout_pass, scene.holdout)):
            for f in frames:
                bucket.append(replace(f, pose=to_ref @ f.pose))
                tags.append(index)
    corners = []
    for scene, t_mm in zip(scenes, transforms):
        box = trimesh.creation.box(bounds=[scene.roi_min, scene.roi_max])
        corners.append(trimesh.transform_points(box.vertices, t_mm))
    corners = np.vstack(corners)
    merged = Scene(replace(ref.config), train, holdout, np.eye(4), corners.min(axis=0), corners.max(axis=0),
                   np.empty((0, 3)), np.empty((0, 3)), np.empty((0, 3)), table_closure=False,
                   train_pass=train_pass, holdout_pass=holdout_pass)
    merged.roi_min[2] = -ref.config.margin_mm
    merged.train_points, merged.train_cameras = part_points(merged, train)
    merged.holdout_points, _ = part_points(merged, holdout)
    return merged
