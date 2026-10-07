"""Synthetic captures from a known mesh, so algorithms can be scored against ground truth.

The part (mm) rests on a table at z = 0; cameras orbit above it and look at its centre, like a person
walking around a part on a desk. The bottom face is therefore never seen — as in a real single-pass scan.

Noise presets are starting estimates (PRD §2 "doğrula"); FR-22.5 sensor tests on the real
iPhone 17 Pro Max should replace them.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import open3d as o3d
import trimesh

from .capture import ARKIT_TO_CV, Capture, DepthFrame


@dataclass(frozen=True)
class SensorModel:
    name: str
    width: int
    height: int
    hfov_deg: float
    distance_m: float           # orbit radius
    noise_a_m: float            # σ(d) = a + b·d²
    noise_b: float
    min_range_m: float
    max_range_m: float
    pose_trans_sigma_m: float   # per-frame tracking error
    pose_rot_sigma_deg: float
    edge_jump_m: float = 0.02   # depth discontinuity that produces flying pixels
    grazing_deg: float = 72.0   # beyond this incidence angle returns drop out

    def sigma(self, d: np.ndarray) -> np.ndarray:
        return self.noise_a_m + self.noise_b * d * d


LIDAR = SensorModel("lidar", 256, 192, 63.0, 0.40, 0.0015, 0.020, 0.20, 5.0, 0.0010, 0.10)
TRUEDEPTH = SensorModel("truedepth", 640, 480, 57.0, 0.28, 0.0002, 0.0050, 0.15, 0.60, 0.0003, 0.05)
SENSORS = {"lidar": LIDAR, "truedepth": TRUEDEPTH}


def _look_at(eye: np.ndarray, target: np.ndarray) -> np.ndarray:
    """ARKit-style camera→world pose looking from `eye` at `target` with world +Z up."""
    back = eye - target
    back /= np.linalg.norm(back)
    right = np.cross([0.0, 0.0, 1.0], back)
    if np.linalg.norm(right) < 1e-6:
        right = np.array([1.0, 0.0, 0.0])
    right /= np.linalg.norm(right)
    up = np.cross(back, right)
    pose = np.eye(4)
    pose[:3, 0], pose[:3, 1], pose[:3, 2], pose[:3, 3] = right, up, back, eye
    return pose


def orbit_poses(center: np.ndarray, radius: float, elevations_deg=(20, 45, 70), per_ring: int = 12,
                seed: int = 0) -> list[np.ndarray]:
    rng = np.random.default_rng(seed)
    poses = []
    for ring, el in enumerate(elevations_deg):
        offset = rng.uniform(0, 360 / per_ring)
        for k in range(per_ring):
            az = np.radians(offset + k * 360 / per_ring)
            e = np.radians(el)
            eye = center + radius * np.array([np.cos(e) * np.cos(az), np.cos(e) * np.sin(az), np.sin(e)])
            poses.append(_look_at(eye, center))
    return poses


def _perturb(pose: np.ndarray, sensor: SensorModel, rng: np.random.Generator) -> np.ndarray:
    axis = rng.normal(size=3)
    axis /= np.linalg.norm(axis)
    angle = np.radians(rng.normal(0, sensor.pose_rot_sigma_deg))
    delta = trimesh.transformations.rotation_matrix(angle, axis)
    delta[:3, 3] = rng.normal(0, sensor.pose_trans_sigma_m, 3)
    return delta @ pose


def simulate_capture(part_mm: trimesh.Trimesh, sensor: SensorModel = LIDAR, seed: int = 0,
                     with_table: bool = True, per_ring: int = 12) -> tuple[Capture, list[np.ndarray]]:
    """Returns the capture (with tracking noise baked into the *reported* poses) and the true poses."""
    rng = np.random.default_rng(seed)
    part = part_mm.copy()
    part.apply_translation([-part.bounds[:, 0].mean(), -part.bounds[:, 1].mean(), -part.bounds[0, 2]])
    part.apply_scale(0.001)  # → meters
    scene = o3d.t.geometry.RaycastingScene()
    scene.add_triangles(o3d.t.geometry.TriangleMesh.from_legacy(_o3d(part)))
    if with_table:
        table = trimesh.creation.box((1.2, 1.2, 0.02))
        table.apply_translation((0, 0, -0.01))
        scene.add_triangles(o3d.t.geometry.TriangleMesh.from_legacy(_o3d(table)))

    center = np.array([0.0, 0.0, part.extents[2] / 2])
    fx = sensor.width / 2 / np.tan(np.radians(sensor.hfov_deg / 2))
    K = np.array([[fx, 0, sensor.width / 2], [0, fx, sensor.height / 2], [0, 0, 1]])
    true_poses = orbit_poses(center, sensor.distance_m, per_ring=per_ring, seed=seed)
    frames = []
    for pose in true_poses:
        extr = ARKIT_TO_CV @ np.linalg.inv(pose)
        rays = o3d.t.geometry.RaycastingScene.create_rays_pinhole(
            o3d.core.Tensor(K), o3d.core.Tensor(extr), sensor.width, sensor.height)
        ans = scene.cast_rays(rays)
        t = ans["t_hit"].numpy()
        dirs = rays.numpy()[..., 3:]
        normals = ans["primitive_normals"].numpy()
        hit = np.isfinite(t)
        pts = rays.numpy()[..., :3] + dirs * np.where(hit, t, 0)[..., None]
        cam = (np.c_[pts.reshape(-1, 3), np.ones(pts.size // 3)] @ extr.T)[:, 2].reshape(t.shape)
        depth = np.where(hit, cam, 0.0)

        # Incidence angle → dropout and lower confidence at grazing views.
        unit = dirs / np.linalg.norm(dirs, axis=-1, keepdims=True)
        cos_inc = np.abs(np.einsum("hwc,hwc->hw", unit, normals))
        grazing = cos_inc < np.cos(np.radians(sensor.grazing_deg))
        drop = grazing & (rng.random(t.shape) < 0.8)
        conf = np.full(t.shape, 2, np.uint8)
        conf[cos_inc < 0.5] = 1

        noisy = depth + rng.normal(size=t.shape) * sensor.sigma(depth) / np.maximum(cos_inc, 0.3) ** 0.5

        # Flying pixels at depth discontinuities: mixed depths with low confidence.
        jump = np.zeros_like(hit)
        for axis in (0, 1):
            diff = np.abs(np.diff(depth, axis=axis)) > sensor.edge_jump_m
            pad = [(0, 1), (0, 0)] if axis == 0 else [(0, 0), (0, 1)]
            jump |= np.pad(diff, pad) | np.pad(diff, [(1, 0), (0, 0)] if axis == 0 else [(0, 0), (1, 0)])
        mix = rng.random(t.shape)
        neighbour = np.maximum(np.roll(depth, 1, 0), np.roll(depth, 1, 1))
        noisy = np.where(jump, depth * mix + neighbour * (1 - mix), noisy)
        conf[jump] = np.where(rng.random(jump.sum()) < 0.7, 0, 1)

        valid = hit & ~drop & (depth >= sensor.min_range_m) & (depth <= sensor.max_range_m)
        frames.append(DepthFrame(np.where(valid, noisy, 0).astype(np.float32), np.where(valid, conf, 0).astype(np.uint8),
                                 fx, fx, sensor.width / 2, sensor.height / 2, _perturb(pose, sensor, rng)))
    return Capture(sensor.name, frames), true_poses


def placed_truth(part_mm: trimesh.Trimesh) -> trimesh.Trimesh:
    """The truth mesh in the simulator's frame, in mm (centred in XY, resting on z = 0)."""
    m = part_mm.copy()
    m.apply_translation([-m.bounds[:, 0].mean(), -m.bounds[:, 1].mean(), -m.bounds[0, 2]])
    return m


def _o3d(m: trimesh.Trimesh) -> o3d.geometry.TriangleMesh:
    return o3d.geometry.TriangleMesh(o3d.utility.Vector3dVector(np.asarray(m.vertices, float)),
                                     o3d.utility.Vector3iVector(np.asarray(m.faces, np.int32)))
