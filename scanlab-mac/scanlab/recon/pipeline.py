"""Multi-algorithm reconstruction and ground-truth-free selection of the best result.

1. Split frames: every `holdout_every`-th frame is kept out for validation.
2. Find the table (RANSAC plane), express everything in a table frame (z = 0 on the table, mm).
3. Run each candidate algorithm on the training frames.
4. Post-process every candidate the same way: largest body, close it, cut flat at the table.
5. Blind score (no CAD needed):
   recall    — share of held-out points within τ of the surface (frames the algorithm never saw),
   precision — share of surface samples that do not sit in space the cameras saw as empty
               (free-space violations = invented surface), F = harmonic mean.
   Unseen regions (the bottom, deep pockets) are neither rewarded nor punished.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np
import open3d as o3d
import trimesh

from ..core import repair
from .capture import Capture, DepthFrame


@dataclass(frozen=True)
class ReconConfig:
    sensor: str
    voxel_mm: float          # point cloud spacing
    tau_mm: float            # blind-score distance threshold
    margin_mm: float         # points closer than this to the table are table
    tsdf_voxels_mm: tuple[float, ...]
    poisson_depths: tuple[int, ...]
    normal_radius_mm: float  # ≈ 3–4 × sensor noise at working distance
    holdout_every: int = 5


CONFIGS = {
    "lidar": ReconConfig("lidar", 1.5, 6.0, 6.0, (2.0, 3.0, 5.0), (7, 8, 9), 8.0),
    "truedepth": ReconConfig("truedepth", 0.4, 0.8, 1.0, (0.5, 1.0, 2.0), (8, 9, 10), 2.0),
}


@dataclass
class Candidate:
    name: str
    mesh: trimesh.Trimesh | None
    seconds: float
    error: str | None = None
    blind: dict = field(default_factory=dict)
    truth: dict = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return self.mesh is not None and len(self.mesh.faces) > 0


@dataclass
class Scene:
    """Capture split and expressed in the table frame."""
    config: ReconConfig
    train: list[DepthFrame]
    holdout: list[DepthFrame]
    world_to_table: np.ndarray       # 4×4, meters → table frame in meters (z up from the table)
    roi_min: np.ndarray              # mm, table frame
    roi_max: np.ndarray
    train_points: np.ndarray         # (n, 3) mm, table frame, inside ROI
    train_cameras: np.ndarray        # (n, 3) mm, camera centre that saw each point
    holdout_points: np.ndarray       # (m, 3) mm
    # False for merged multi-pass scenes: the underside was observed, so no table footprint/closure.
    table_closure: bool = True
    # Merged scenes only: which pass each train/holdout frame came from.
    train_pass: list[int] = field(default_factory=list)
    holdout_pass: list[int] = field(default_factory=list)
    low_points: np.ndarray = field(default_factory=lambda: np.empty((0, 3)))   # 0 < z ≤ margin, in ROI
    band_points: np.ndarray = field(default_factory=lambda: np.empty((0, 3)))  # z ≤ margin, in ROI (table level)
    low_cameras: np.ndarray = field(default_factory=lambda: np.empty((0, 3)))

    def to_table_mm(self, world_m: np.ndarray) -> np.ndarray:
        return trimesh.transform_points(world_m, self.world_to_table) * 1000.0

    def in_roi(self, p_mm: np.ndarray) -> np.ndarray:
        return np.all((p_mm >= self.roi_min) & (p_mm <= self.roi_max), axis=1)


# ── Scene preparation ───────────────────────────────────────────────────────

def _frame_points(frames: list[DepthFrame], min_conf: int) -> tuple[np.ndarray, np.ndarray]:
    pts, cams = [], []
    for f in frames:
        p, _ = f.points(min_conf)
        pts.append(p)
        cams.append(np.repeat(f.camera_center[None], len(p), axis=0))
    return np.vstack(pts), np.vstack(cams)


def focus_point(frames: list[DepthFrame]) -> np.ndarray:
    """Least-squares point closest to every camera's viewing ray: where the user aimed the phone."""
    a = np.zeros((3, 3))
    b = np.zeros(3)
    for f in frames:
        d = -f.pose[:3, 2]  # ARKit cameras look down −Z
        d /= np.linalg.norm(d)
        proj = np.eye(3) - np.outer(d, d)
        a += proj
        b += proj @ f.camera_center
    return np.linalg.lstsq(a, b, rcond=None)[0]


def prepare_scene(capture: Capture, config: ReconConfig) -> Scene:
    frames = capture.frames
    holdout = [f for i, f in enumerate(frames) if i % config.holdout_every == 0]
    train = [f for i, f in enumerate(frames) if i % config.holdout_every != 0]
    pts, cams = _frame_points(train, 2)

    # 1. Table plane (largest plane), normal pointing at the cameras.
    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(pts))
    plane, inliers = pcd.segment_plane(distance_threshold=config.margin_mm / 1000 * 2, ransac_n=3,
                                       num_iterations=2000)
    n = np.asarray(plane[:3])
    d = plane[3] / np.linalg.norm(n)
    n = n / np.linalg.norm(n)
    if np.dot(n, cams.mean(axis=0)) + d < 0:
        n, d = -n, -d
    to_table = trimesh.geometry.align_vectors(n, [0, 0, 1])
    to_table[:3, 3] = [0, 0, d]  # signed distance to the plane becomes z

    tp = trimesh.transform_points(pts, to_table) * 1000
    # 2. Table thickness from the data: 4σ of the plane inliers' residuals, never below the preset.
    sigma = float(np.std(tp[np.asarray(inliers), 2]))
    margin = max(config.margin_mm, 4 * sigma)
    above = tp[:, 2] > margin

    # 3. The part is the cluster the cameras were aimed at (not simply the biggest one).
    focus = trimesh.transform_points(focus_point(train)[None], to_table)[0] * 1000
    v = config.voxel_mm
    keys = np.floor(tp[above] / v).astype(np.int64)
    _, idx = np.unique(keys, axis=0, return_index=True)
    sparse = tp[above][idx]
    labels = np.asarray(o3d.geometry.PointCloud(o3d.utility.Vector3dVector(sparse))
                        .cluster_dbscan(eps=v * 3, min_points=8))
    if labels.max() < 0:
        raise ValueError(f"no object found above the table: with this sensor's noise the table band is "
                         f"{margin:.1f} mm, so thinner parts cannot be separated from the table "
                         f"(use TrueDepth / move closer, or stand the part on a riser)")
    best, best_d = -1, np.inf
    for lab in range(labels.max() + 1):
        cluster = sparse[labels == lab]
        if len(cluster) < 50:
            continue
        dist = float(np.min(np.linalg.norm(cluster[:, :2] - focus[:2], axis=1)))
        if dist < best_d:
            best, best_d = lab, dist
    if best < 0:
        raise ValueError("no sizeable object near where the cameras were aimed")
    obj = sparse[labels == best]
    pad = v * 4
    roi_min = np.r_[obj[:, :2].min(axis=0) - pad, -margin]
    roi_max = obj.max(axis=0) + pad

    cfg = ReconConfig(**{**config.__dict__, "margin_mm": margin})
    scene = Scene(cfg, train, holdout, to_table, roi_min, roi_max, np.empty((0, 3)), np.empty((0, 3)),
                  np.empty((0, 3)))
    keep = scene.in_roi(tp) & (tp[:, 2] > margin)
    scene.train_points = tp[keep]
    scene.train_cameras = trimesh.transform_points(cams[keep], to_table) * 1000
    scene.band_points = tp[scene.in_roi(tp) & (tp[:, 2] <= margin)]
    low = scene.in_roi(tp) & (tp[:, 2] > 0) & (tp[:, 2] <= margin)
    scene.low_points = tp[low]
    scene.low_cameras = trimesh.transform_points(cams[low], to_table) * 1000
    hp, _ = _frame_points(holdout, 2)
    htp = scene.to_table_mm(hp)
    scene.holdout_points = htp[scene.in_roi(htp) & (htp[:, 2] > margin)]
    label_part_pixels(scene)
    return scene


def label_part_pixels(scene: Scene) -> None:
    """Sets `frame.part` for every frame: pixels whose 3D point belongs to the part."""
    for f in scene.train + scene.holdout:
        pts, mask = f.points(1)
        part = np.zeros_like(mask)
        part[mask] = part_mask(scene, scene.to_table_mm(pts), strict=True)
        f.part = part


# ── Candidates ──────────────────────────────────────────────────────────────

def footprint_points(scene: Scene, band_mm: float | None = None) -> np.ndarray:
    """Points on the table (z = 0) under the part's contact area — the part's unseen bottom.

    Contact area = top-view occupancy of the points within `band_mm` above the table, closed
    morphologically so the scan's gaps along the base don't punch holes in it.
    """
    from scipy import ndimage

    if not scene.table_closure:
        return np.empty((0, 3))
    v = scene.config.voxel_mm
    band = band_mm if band_mm is not None else scene.config.margin_mm + 4 * v
    low = scene.train_points[scene.train_points[:, 2] < band]
    if len(low) < 10:
        return np.empty((0, 3))
    origin = low[:, :2].min(axis=0) - 4 * v
    ij = np.floor((low[:, :2] - origin) / v).astype(int)
    grid = np.zeros(ij.max(axis=0) + 9, bool)
    grid[ij[:, 0], ij[:, 1]] = True
    grid = ndimage.binary_closing(grid, iterations=3)
    grid = ndimage.binary_fill_holes(grid) & ndimage.binary_closing(grid, iterations=6)
    cells = np.argwhere(grid)
    xy = origin + (cells + 0.5) * v
    return np.c_[xy, np.zeros(len(xy))]


def in_footprint(scene: Scene, xy: np.ndarray, dilate: int = 1) -> np.ndarray:
    """Top-view test: is each (x, y) on the part's contact area (dilated by `dilate` voxels)?"""
    from scipy import ndimage

    foot = footprint_points(scene)
    if len(foot) == 0:
        return np.zeros(len(xy), bool)
    v = scene.config.voxel_mm
    origin = foot[:, :2].min(axis=0) - 2 * v
    ij = np.floor((foot[:, :2] - origin) / v).astype(int)
    grid = np.zeros(ij.max(axis=0) + 4, bool)
    grid[ij[:, 0], ij[:, 1]] = True
    if dilate:
        grid = ndimage.binary_dilation(grid, iterations=dilate)
    q = np.floor((xy - origin) / v).astype(int)
    inside = np.all((q >= 0) & (q < grid.shape), axis=1)
    inside[inside] = grid[q[inside, 0], q[inside, 1]]
    return inside


def part_mask(scene: Scene, p_mm: np.ndarray, strict: bool = False) -> np.ndarray:
    """In the ROI and either above the table band or on the part's contact area (not table).

    strict=True labels *measured pixels*: wall bases only on the contact area itself and in the upper
    half of the band — lower down, table and wall bottom are indistinguishable in noise, and table
    points just outside the base became a fake flange (after flipping: fake obstacles in mid-air).
    strict=False filters *reconstructed faces*: it must keep a closed base the algorithm put on the
    table (z ≈ 0) under the part, so it uses the dilated contact area down to −margin.
    """
    roi = scene.in_roi(p_mm)
    if not scene.table_closure:
        return roi
    low = roi & (p_mm[:, 2] <= scene.config.margin_mm)
    keep = roi & ~low
    if low.any():
        if strict:
            keep[low] = (in_footprint(scene, p_mm[low, :2], dilate=0)
                         & (p_mm[low, 2] > 0.5 * scene.config.margin_mm))
        else:
            keep[low] = in_footprint(scene, p_mm[low, :2], dilate=1) & (p_mm[low, 2] > -scene.config.margin_mm)
    return keep


def wall_base_points(scene: Scene) -> tuple[np.ndarray, np.ndarray]:
    """Points in the table band (0 < z ≤ margin) that sit on the part's contact area: the bottom of
    its walls, not the table. Without them every algorithm has to guess the last few millimetres."""
    if len(scene.low_points) == 0:
        return np.empty((0, 3)), np.empty((0, 3))
    inside = in_footprint(scene, scene.low_points[:, :2])
    return scene.low_points[inside], scene.low_cameras[inside]


def _point_cloud(scene: Scene, with_footprint: bool = True) -> o3d.geometry.PointCloud:
    v = scene.config.voxel_mm
    pts, cams_all = scene.train_points, scene.train_cameras
    if with_footprint:
        wp, wc = wall_base_points(scene)
        pts, cams_all = np.vstack([pts, wp]), np.vstack([cams_all, wc])
    keys = np.floor(pts / v).astype(np.int64)
    _, idx = np.unique(keys, axis=0, return_index=True)
    pcd = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(pts[idx]))
    pcd, kept = pcd.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)
    cams = cams_all[idx][kept]
    # The neighbourhood must be several times the sensor noise, or normals follow the noise
    # (a flat face measured 8 % of its normals pointing down with a 30-NN search).
    pcd.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=scene.config.normal_radius_mm, max_nn=120))
    normals = np.asarray(pcd.normals)
    flip = np.einsum("ij,ij->i", normals, cams - np.asarray(pcd.points)) < 0
    normals[flip] *= -1
    points = np.asarray(pcd.points)
    if with_footprint:
        foot = footprint_points(scene)
        points = np.vstack([points, foot])
        normals = np.vstack([normals, np.tile([0.0, 0.0, -1.0], (len(foot), 1))])
    out = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(points))
    out.normals = o3d.utility.Vector3dVector(normals)
    return out


def _to_trimesh(m: o3d.geometry.TriangleMesh) -> trimesh.Trimesh:
    return trimesh.Trimesh(np.asarray(m.vertices), np.asarray(m.triangles), process=True)


def tsdf(scene: Scene, voxel_mm: float) -> trimesh.Trimesh:
    """Truncated signed distance fusion of the masked depth frames (Open3D tensor VoxelBlockGrid)."""
    import open3d.core as o3c

    vs = voxel_mm / 1000
    grid = o3d.t.geometry.VoxelBlockGrid(attr_names=("tsdf", "weight"), attr_dtypes=(o3c.float32, o3c.float32),
                                         attr_channels=((1), (1)), voxel_size=vs, block_resolution=8,
                                         block_count=200_000)
    for f in scene.train:
        # Keep only pixels that land in the region of interest (drops table and clutter).
        if scene.table_closure or f.part is None:
            # Single pass: lenient mask keeps the full wall bases down to the table band.
            pts, valid = f.points(1)
            keep_px = np.zeros_like(valid)
            keep_px[valid] = part_mask(scene, scene.to_table_mm(pts))
        else:
            keep_px = f.part  # merged passes: strict labels, no table flange from any pass
        depth = o3d.t.geometry.Image(o3c.Tensor(np.where(keep_px, f.depth, 0).astype(np.float32)))
        K = o3c.Tensor(np.array([[f.fx, 0, f.cx], [0, f.fy, f.cy], [0, 0, 1]]), o3c.float64)
        E = o3c.Tensor(f.extrinsic_cv(), o3c.float64)
        coords = grid.compute_unique_block_coordinates(depth, K, E, 1.0, 10.0, trunc_voxel_multiplier=4.0)
        grid.integrate(coords, depth, K, E, 1.0, 10.0, trunc_voxel_multiplier=4.0)
    legacy = grid.extract_triangle_mesh().to_legacy()
    mesh = _to_trimesh(legacy)
    mesh.apply_transform(scene.world_to_table)
    mesh.apply_scale(1000.0)
    return mesh


def poisson(scene: Scene, depth: int) -> trimesh.Trimesh:
    """Screened Poisson via PyMeshLab (Open3D's build aborted the process on real-looking input)."""
    import pymeshlab

    pcd = _point_cloud(scene)
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=np.asarray(pcd.points), v_normals_matrix=np.asarray(pcd.normals)))
    ms.generate_surface_reconstruction_screened_poisson(depth=depth, scale=1.1, preclean=True, threads=2)
    m = ms.current_mesh()
    # No density trimming: with the table footprint as the bottom the surface closes where it should;
    # trimming left ragged openings whose caps folded into the part.
    return trimesh.Trimesh(m.vertex_matrix(), m.face_matrix(), process=True)


def tsdf_poisson(scene: Scene, voxel_mm: float, depth: int = 9) -> trimesh.Trimesh:
    """TSDF where the part was seen, screened Poisson to close what was not (underside, deep pockets).

    TSDF averages many depth maps along the rays (accurate visible surface) but leaves unseen regions
    open; Poisson closes smoothly but blurs. Sampling the TSDF surface + the table footprint and
    re-solving with Poisson keeps the former and gets the latter.
    """
    import pymeshlab

    surface = tsdf(scene, voxel_mm)
    surface.update_faces(part_mask(scene, surface.triangles_center))
    surface.remove_unreferenced_vertices()
    if len(surface.faces) == 0:
        raise ValueError("empty TSDF surface")
    surface = max(surface.split(only_watertight=False), key=lambda p: p.area)
    count = int(min(400_000, max(20_000, surface.area / (scene.config.voxel_mm ** 2))))
    pts, fi = trimesh.sample.sample_surface_even(surface, count, seed=np.random.default_rng(0))
    normals = surface.face_normals[fi]
    foot = footprint_points(scene)
    pts = np.vstack([pts, foot])
    normals = np.vstack([normals, np.tile([0.0, 0.0, -1.0], (len(foot), 1))])
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pts, v_normals_matrix=normals))
    ms.generate_surface_reconstruction_screened_poisson(depth=depth, scale=1.1, preclean=True, threads=2)
    m = ms.current_mesh()
    return trimesh.Trimesh(m.vertex_matrix(), m.face_matrix(), process=True)


def ball_pivoting(scene: Scene) -> trimesh.Trimesh:
    pcd = _point_cloud(scene)
    spacing = float(np.mean(pcd.compute_nearest_neighbor_distance()))
    radii = o3d.utility.DoubleVector([spacing * k for k in (1.5, 3, 6)])
    return _to_trimesh(o3d.geometry.TriangleMesh.create_from_point_cloud_ball_pivoting(pcd, radii))


def algorithms(config: ReconConfig) -> dict[str, Callable[[Scene], trimesh.Trimesh]]:
    algos: dict[str, Callable[[Scene], trimesh.Trimesh]] = {}
    for v in config.tsdf_voxels_mm:
        algos[f"tsdf_{v:g}mm"] = lambda s, v=v: tsdf(s, v)
    for d in config.poisson_depths:
        algos[f"poisson_d{d}"] = lambda s, d=d: poisson(s, d)
    v_fine = min(config.tsdf_voxels_mm)
    algos[f"tsdf_poisson_{v_fine:g}mm"] = lambda s, v=v_fine: tsdf_poisson(s, v)
    algos["ball_pivoting"] = ball_pivoting
    return algos


# ── Shared post-processing: one closed body with a flat base on the table ──────

MAX_FACES = 600_000


def inner_floor_height(ring, scene: Scene) -> float | None:
    """None when the points observed inside `ring` (top view) sit at table height — the cameras looked
    through an opening onto the table. Otherwise the inner floor's height (median of those points)."""
    import shapely

    pts = scene.band_points
    if len(pts) == 0:
        return None
    inside = shapely.contains_xy(ring, pts[:, 0], pts[:, 1])
    if inside.sum() < 30:
        return None  # nothing seen inside: an opening too narrow to look into — keep it open
    z = float(np.median(pts[inside, 2]))
    return None if z < 0.25 * scene.config.margin_mm else z


def finalize(mesh: trimesh.Trimesh, scene: Scene) -> trimesh.Trimesh:
    m = mesh.copy()
    m.update_faces(m.nondegenerate_faces())
    m.remove_unreferenced_vertices()
    m.update_faces(part_mask(scene, m.triangles_center))
    m.remove_unreferenced_vertices()
    parts = m.split(only_watertight=False)
    if not parts:
        raise ValueError("nothing left inside the region of interest")
    m = max(parts, key=lambda p: p.area)
    if len(m.faces) > MAX_FACES:
        m = m.simplify_quadric_decimation(face_count=MAX_FACES)
    if not m.is_watertight:
        # Small gaps in the visible surface first, then the unseen base (the table), MeshFix last.
        m, _ = repair.fill_holes(m, max_perimeter_mm=20 * scene.config.voxel_mm)
        if not m.is_watertight and scene.table_closure:
            from .closure import close_on_table

            try:
                closed, _ = close_on_table(m, band_mm=scene.config.margin_mm + 4 * scene.config.voxel_mm,
                                           classify=lambda ring: inner_floor_height(ring, scene))
                if closed.is_watertight:
                    m = closed
            except ValueError:
                pass
        if not m.is_watertight:
            m, _ = repair.fill_holes(m, max_perimeter_mm=1e9)
        if not m.is_watertight:
            m, _ = repair.repair_full(m)
    # The part rests on the table: everything below z = 0 is either noise or a closing cap.
    big = float(m.extents.max()) * 4 + 50
    upper = trimesh.creation.box((big, big, big))
    upper.apply_translation(np.r_[m.bounds.mean(axis=0)[:2], big / 2])
    cut = m.intersection(upper, engine="manifold")
    return cut if len(cut.faces) else m


# ── Scores ──────────────────────────────────────────────────────────────────

def _surface_distance(mesh: trimesh.Trimesh, points: np.ndarray) -> np.ndarray:
    """Exact unsigned point-to-mesh distance (Open3D, embree BVH)."""
    if len(points) == 0:
        return np.empty(0)
    scene = o3d.t.geometry.RaycastingScene()
    scene.add_triangles(o3d.core.Tensor(np.asarray(mesh.vertices, np.float32)),
                        o3d.core.Tensor(np.asarray(mesh.faces, np.uint32)))
    return scene.compute_distance(o3d.core.Tensor(np.asarray(points, np.float32))).numpy().astype(np.float64)


class FreeSpace:
    """Per-frame observation maps, filtered once, for fast free-space queries.

    A point is "in free space" for a frame when it lies clearly in front of the nearest confident
    observation in a `window`×`window` neighbourhood (whole window valid), so points on a silhouette
    do not count just because their rounded pixel saw the table behind the part.
    """

    def __init__(self, scene: Scene, window: int = 5):
        from scipy import ndimage

        self.scene = scene
        self.maps = []
        for f in scene.train + scene.holdout:
            good = (f.depth > 0) & (f.confidence >= 2)
            near = ndimage.minimum_filter(np.where(good, f.depth, np.inf), size=window)
            all_good = ndimage.minimum_filter(good.astype(np.uint8), size=window).astype(bool)
            self.maps.append((f, near, all_good))
        self.table_to_world = np.linalg.inv(scene.world_to_table)

    def rate(self, points_mm: np.ndarray, slack_mm: float, min_frames: int = 2) -> float:
        if len(points_mm) == 0:
            return 0.0
        world = trimesh.transform_points(points_mm / 1000.0, self.table_to_world)
        hits = np.zeros(len(points_mm), int)
        for f, near, all_good in self.maps:
            cam = trimesh.transform_points(world, f.extrinsic_cv())
            z = cam[:, 2]
            safe = np.maximum(z, 1e-9)
            u = np.round(cam[:, 0] / safe * f.fx + f.cx).astype(int)
            v = np.round(cam[:, 1] / safe * f.fy + f.cy).astype(int)
            w, h = f.size
            ok = (z > 0) & (u >= 0) & (u < w) & (v >= 0) & (v < h)
            obs = np.full(len(points_mm), np.inf)
            obs[ok] = near[v[ok], u[ok]]
            valid = np.zeros(len(points_mm), bool)
            valid[ok] = all_good[v[ok], u[ok]]
            hits += valid & (z * 1000 < obs * 1000 - slack_mm)
        return float(np.mean(hits >= min_frames))


def free_space_rate(points_mm: np.ndarray, scene: Scene, slack_mm: float, min_frames: int = 2,
                    window: int = 5) -> float:
    return FreeSpace(scene, window).rate(points_mm, slack_mm, min_frames)


def free_space_violations(mesh: trimesh.Trimesh, scene: Scene, samples: int = 4000, seed: int = 0) -> float:
    """Share of surface samples in observed free space (invented surface)."""
    pts, _ = trimesh.sample.sample_surface(mesh, samples, seed=np.random.default_rng(seed))
    if scene.table_closure:
        pts = pts[pts[:, 2] > scene.config.margin_mm]  # the closing cap on the table is unobservable
    return free_space_rate(pts, scene, 2 * scene.config.tau_mm, window=3)


def depth_consistency(mesh: trimesh.Trimesh, scene: Scene) -> dict:
    """Renders the candidate into the held-out views and compares depth *along each camera ray*.

    This is what the sensor actually measures. Point-to-nearest-surface distance (the older score)
    rewards surfaces that pass between noisy points — i.e. over-smoothed, rounded ones; per-ray depth
    residuals average the noise out over ~10⁵ pixels and expose small systematic offsets.
    """
    rs = o3d.t.geometry.RaycastingScene()
    rs.add_triangles(o3d.core.Tensor(np.asarray(mesh.vertices, np.float32)),
                     o3d.core.Tensor(np.asarray(mesh.faces, np.uint32)))
    tau = scene.config.tau_mm
    residuals, covered, total, extra, background, missed = [], 0, 0, 0, 0, 0
    for f in scene.holdout:
        pts, px = f.points(2)
        tp = scene.to_table_mm(pts)
        obj = f.part[px] if f.part is not None else scene.in_roi(tp) & (tp[:, 2] > scene.config.margin_mm)
        cam = trimesh.transform_points(f.camera_center[None], scene.world_to_table)[0] * 1000
        dirs = tp - cam
        dist = np.linalg.norm(dirs, axis=1)
        dirs /= dist[:, None]
        rays = np.c_[np.repeat(cam[None], len(tp), axis=0), dirs].astype(np.float32)
        hit = rs.cast_rays(o3d.core.Tensor(rays))["t_hit"].numpy()
        both = obj & np.isfinite(hit)
        residuals.append(hit[both] - dist[both])
        covered += int(both.sum())
        total += int(obj.sum())
        missed += int((obj & ~np.isfinite(hit)).sum())
        # Candidate surface in front of something the camera saw behind it = invented geometry.
        extra += int((~obj & np.isfinite(hit) & (hit < dist - 3 * tau)).sum())
        background += int((~obj).sum())
    r = np.concatenate(residuals) if residuals else np.empty(0)
    clip = 3 * tau
    # One score, no ad-hoc guards: pixels the candidate misses and pixels where it invents surface
    # count as maximal (clipped) errors, so shrinking a part or inflating it cannot buy a lower RMSE.
    sq = np.r_[np.minimum(r * r, clip * clip), np.full(missed + extra, clip * clip)]
    return {
        "depth_rmse_mm": round(float(np.sqrt(np.mean(sq))), 4) if len(sq) else None,
        "inlier_rmse_mm": round(float(np.sqrt(np.mean(np.minimum(r * r, clip * clip)))), 4) if len(r) else None,
        "depth_bias_mm": round(float(np.median(r)), 4) if len(r) else None,
        "coverage": round(covered / max(total, 1), 4),
        "extra_rate": round(extra / max(background, 1), 5),
        "holdout_pixels": total,
    }


def blind_score(mesh: trimesh.Trimesh, scene: Scene) -> dict:
    tau = scene.config.tau_mm
    hold = scene.holdout_points
    if len(hold) > 20000:
        hold = hold[np.random.default_rng(0).choice(len(hold), 20000, replace=False)]
    d = _surface_distance(mesh, hold)
    recall = float(np.mean(d < tau))
    precision = 1.0 - free_space_violations(mesh, scene)
    f = 0.0 if recall + precision == 0 else 2 * precision * recall / (precision + recall)
    return {"f": round(f, 4), "precision": round(precision, 4), "recall": round(recall, 4),
            "holdout_median_mm": round(float(np.median(d)), 3), **depth_consistency(mesh, scene)}


def truth_score(mesh: trimesh.Trimesh, truth_mm: trimesh.Trimesh, tau_mm: float, samples: int = 20000) -> dict:
    """Tanks-and-Temples style F-score against the CAD truth (benchmark only)."""
    rng = np.random.default_rng(1)
    a, _ = trimesh.sample.sample_surface(mesh, samples, seed=rng)
    b, _ = trimesh.sample.sample_surface(truth_mm, samples, seed=rng)
    da = _surface_distance(truth_mm, a)
    db = _surface_distance(mesh, b)
    p, r = float(np.mean(da < tau_mm)), float(np.mean(db < tau_mm))
    f = 0.0 if p + r == 0 else 2 * p * r / (p + r)
    return {"f": round(f, 4), "precision": round(p, 4), "recall": round(r, 4),
            "chamfer_mm": round(float((da.mean() + db.mean()) / 2), 3), "p95_mm": round(float(np.percentile(np.r_[da, db], 95)), 3)}


# ── Orchestration ───────────────────────────────────────────────────────────

def _run_one(scene: Scene, name: str) -> Candidate:
    t = time.time()
    try:
        mesh = finalize(algorithms(scene.config)[name](scene), scene)
        cand = Candidate(name, mesh, round(time.time() - t, 2))
        cand.blind = blind_score(mesh, scene)
        cand.blind["watertight"] = bool(mesh.is_watertight)
        return cand
    except Exception as e:  # report, don't raise: other candidates continue
        return Candidate(name, None, round(time.time() - t, 2), error=f"{type(e).__name__}: {e}")


def reconstruct_all(capture: Capture, only: list[str] | None = None, workers: int = 4,
                    timeout_s: float = 600) -> tuple[Scene, list[Candidate]]:
    """Runs every algorithm in its own process: native libraries can abort() on odd input, and one
    crashing algorithm must never take down the others (or the MCP server)."""
    import multiprocessing as mp
    from concurrent.futures import ProcessPoolExecutor
    from concurrent.futures.process import BrokenProcessPool

    return reconstruct_scene(prepare_scene(capture, CONFIGS[capture.sensor]), only, workers, timeout_s)


def reconstruct_scene(scene: Scene, only: list[str] | None = None, workers: int = 4,
                      timeout_s: float = 600) -> tuple[Scene, list[Candidate]]:
    """Same as `reconstruct_all` for a prepared (possibly merged multi-pass) scene."""
    import multiprocessing as mp
    from concurrent.futures import ProcessPoolExecutor
    from concurrent.futures.process import BrokenProcessPool

    config = scene.config
    names = [n for n in algorithms(config) if not only or n in only]
    ctx = mp.get_context("spawn")
    pools = {n: ProcessPoolExecutor(max_workers=1, mp_context=ctx) for n in names}
    futures = {}
    try:
        # Bounded parallelism: submit in waves of `workers`.
        out: list[Candidate] = []
        for i in range(0, len(names), workers):
            wave = names[i:i + workers]
            futures = {n: pools[n].submit(_run_one, scene, n) for n in wave}
            for n, fut in futures.items():
                t = time.time()
                try:
                    out.append(fut.result(timeout=timeout_s))
                except BrokenProcessPool:
                    out.append(Candidate(n, None, round(time.time() - t, 2), error="crashed (native abort)"))
                except TimeoutError:
                    out.append(Candidate(n, None, timeout_s, error=f"timed out after {timeout_s:.0f}s"))
        return scene, out
    finally:
        for pool in pools.values():
            pool.shutdown(wait=False, cancel_futures=True)


def pass_view(scene: Scene, index: int) -> Scene:
    """The frames of one pass of a merged scene (same frame of reference)."""
    from dataclasses import replace

    train = [f for f, p in zip(scene.train, scene.train_pass) if p == index]
    hold = [f for f, p in zip(scene.holdout, scene.holdout_pass) if p == index]
    return replace(scene, train=train, holdout=hold, train_pass=[index] * len(train),
                   holdout_pass=[index] * len(hold))


def shape_score(mesh: trimesh.Trimesh, merged: Scene) -> dict:
    """Blind score of a candidate's *shape* on every pass, independent of inter-pass alignment error.

    Each pass's frames carry their own tracking/registration offset. Scoring a candidate directly on
    all frames charges that offset to whichever candidate was not built from those frames (it made
    single-pass candidates lose to merged ones that were worse in shape). So the candidate is first
    rigidly snapped (normal-aware ICP) onto each pass's own training points, then scored on that
    pass's held-out frames; the per-pass errors are pooled by pixel count.
    """
    from .multipass import _cloud, icp_normal_aware, part_points

    vox = max(2 * merged.config.voxel_mm, 0.5)
    samples, fi = trimesh.sample.sample_surface_even(mesh, 20_000, seed=np.random.default_rng(0))
    normals = mesh.face_normals[fi]
    total_sq, total_px, parts = 0.0, 0, {}
    for index in sorted(set(merged.holdout_pass)):
        view = pass_view(merged, index)
        pts, cams = part_points(view, view.train)
        cloud = _cloud(pts, cams, vox)
        t, _, _ = icp_normal_aware(samples, normals, np.asarray(cloud.points), np.asarray(cloud.normals),
                                   np.eye(4), (4 * vox, 2 * vox, vox, 0.5 * vox))
        snapped = mesh.copy()
        snapped.apply_transform(t)
        d = depth_consistency(snapped, view)
        parts[f"pass{index}"] = {"depth_rmse_mm": d["depth_rmse_mm"], "pixels": d["holdout_pixels"],
                                 "snap_mm": round(float(np.linalg.norm(t[:3, 3])), 3)}
        if d["depth_rmse_mm"] is not None:
            total_sq += d["depth_rmse_mm"] ** 2 * d["holdout_pixels"]
            total_px += d["holdout_pixels"]
    return {"depth_rmse_mm": round(float(np.sqrt(total_sq / max(total_px, 1))), 4) if total_px else None,
            "per_pass": parts}


# Calibrated on the synthetic benchmark (benchmarks/results_recon_flip.md); see first_pass_check.
FIRST_PASS_INVENTED_MAX = 0.02
FIRST_PASS_MISSING_MAX = 0.05


def first_pass_check(mesh: trimesh.Trimesh, merged: Scene) -> dict:
    """Does what the turned pass saw contradict a first-pass-only candidate? Not circular: the
    candidate never used the turned pass. Two symptoms, both with mm-scale slack so sub-millimetre
    registration error does not matter:
      invented — candidate surface where the turned pass saw empty space (e.g. a solid base filled in
                 under a ring's curved underside),
      missing  — turned-pass points far from the candidate (geometry the first pass never had).
    """
    from .multipass import part_points

    view = pass_view(merged, sorted(set(merged.holdout_pass))[1])
    slack = 3 * merged.config.tau_mm
    samples, _ = trimesh.sample.sample_surface(mesh, 6000, seed=np.random.default_rng(0))
    invented = FreeSpace(view).rate(samples, slack)
    pts, _ = part_points(view, view.train)
    pts = pts[np.random.default_rng(1).choice(len(pts), min(len(pts), 20000), replace=False)]
    missing = float(np.mean(_surface_distance(mesh, pts) > slack))
    return {"invented": round(invented, 4), "missing": round(missing, 4)}


def underside_residual(mesh: trimesh.Trimesh, merged: Scene, band_mm: float) -> float | None:
    """Depth RMSE on the turned pass's held-out pixels that show the first pass's base region
    (z < band_mm in the first pass's table frame), after snapping the candidate onto that pass.

    This is the one question a second pass can answer: was the first pass's guess about the unseen
    base (flat, on the table) right?
    """
    from .multipass import _cloud, icp_normal_aware, part_points

    passes = sorted(set(merged.holdout_pass))
    if len(passes) < 2:
        return None
    view = pass_view(merged, passes[1])
    vox = max(2 * merged.config.voxel_mm, 0.5)
    samples, fi = trimesh.sample.sample_surface_even(mesh, 20_000, seed=np.random.default_rng(0))
    pts, cams = part_points(view, view.train)
    cloud = _cloud(pts, cams, vox)
    t, _, _ = icp_normal_aware(samples, mesh.face_normals[fi], np.asarray(cloud.points),
                               np.asarray(cloud.normals), np.eye(4), (4 * vox, 2 * vox, vox, 0.5 * vox))
    snapped = mesh.copy()
    snapped.apply_transform(t)
    rs = o3d.t.geometry.RaycastingScene()
    rs.add_triangles(o3d.core.Tensor(np.asarray(snapped.vertices, np.float32)),
                     o3d.core.Tensor(np.asarray(snapped.faces, np.uint32)))
    clip = 3 * merged.config.tau_mm
    sq = []
    for f in view.holdout:
        p, px = f.points(2, part_only=True)
        tp = view.to_table_mm(p)
        base = tp[:, 2] < band_mm
        if not base.any():
            continue
        cam = view.to_table_mm(f.camera_center[None])[0]
        dirs = tp[base] - cam
        dist = np.linalg.norm(dirs, axis=1)
        rays = np.c_[np.repeat(cam[None], len(dist), axis=0), dirs / dist[:, None]].astype(np.float32)
        hit = rs.cast_rays(o3d.core.Tensor(rays))["t_hit"].numpy()
        r = np.where(np.isfinite(hit), hit - dist, clip)
        sq.append(np.minimum(r * r, clip * clip))
    if not sq:
        return None
    return float(np.sqrt(np.mean(np.concatenate(sq))))


def reconstruct_passes(captures: list[Capture], only: list[str] | None = None) -> tuple[Scene, list[Candidate], dict]:
    """Flip-and-align (PRD FR-27.5): register the turned pass onto the first, then decide whether the
    second pass is needed at all.

    Two pools: the first pass alone (unseen base closed on the table — exact for parts that sit flat)
    and all passes merged (base observed, but every pass's tracking/alignment error included). The
    turned pass decides between them by checking the first pass's base guess against what it saw.
    If registration is unreliable (e.g. a thin plate that looks the same either way up), the first
    pass alone is returned with an explanation instead of a silently wrong merge.
    """
    from .multipass import merge, register

    if len({c.sensor for c in captures}) != 1:
        raise ValueError("all passes must come from the same sensor")
    config = CONFIGS[captures[0].sensor]
    scenes = [prepare_scene(c, config) for c in captures]
    _, single = reconstruct_scene(scenes[0], only)
    for c in single:
        c.name = f"1pass:{c.name}"
    info: dict = {"used": "1pass"}
    try:
        registrations = [register(s, scenes[0]) for s in scenes[1:]]
    except ValueError as e:
        info["note"] = f"second pass not used: {e}"
        return scenes[0], single, info
    info["registration"] = [r.report() for r in registrations]
    merged = merge(scenes, [np.eye(4)] + [r.transform for r in registrations])
    _, multi = reconstruct_scene(merged, only)
    for c in multi:
        c.name = f"2pass:{c.name}"
        if c.ok:
            c.blind = {**blind_score(c.mesh, merged), **shape_score(c.mesh, merged)}
            c.blind["watertight"] = bool(c.mesh.is_watertight)

    best_single = pick_best(single)
    ok_multi = [c for c in multi if c.ok and c.blind.get("depth_rmse_mm") is not None]
    if not ok_multi:
        info["note"] = "every merged reconstruction failed; first pass used"
        return scenes[0], single, info
    best_multi = pick_best(ok_multi)
    check = first_pass_check(best_single.mesh, merged)
    info["first_pass_check"] = check
    if check["invented"] > FIRST_PASS_INVENTED_MAX or check["missing"] > FIRST_PASS_MISSING_MAX:
        info["used"] = "2pass"
        info["note"] = "the turned pass shows the base is not flat on the table; merged result used"
        return merged, multi + single, info
    info["note"] = "the turned pass confirms the base sits flat on the table; first pass used (cleaner)"
    return scenes[0], single + multi, info


def pick_best(candidates: list[Candidate]) -> Candidate:
    """Lowest held-out depth error (misses and invented surface included, see depth_consistency).

    Validated against CAD truth on the synthetic benchmark (benchmarks/results_recon.md).
    """
    ok = [c for c in candidates if c.ok and c.blind.get("depth_rmse_mm") is not None]
    if not ok:
        raise ValueError("every reconstruction algorithm failed: " +
                         "; ".join(f"{c.name}: {c.error}" for c in candidates if c.error))
    return min(ok, key=lambda c: (c.blind["depth_rmse_mm"], not c.blind["watertight"]))
