"""`deviation_compare`: surface distance between two meshes (M25, M26 deviation budget)."""

from __future__ import annotations

import numpy as np
import trimesh


def _one_way(src: trimesh.Trimesh, dst: trimesh.Trimesh, samples: int, seed: int) -> np.ndarray:
    points, _ = trimesh.sample.sample_surface(src, samples, seed=np.random.default_rng(seed))
    _, distance, _ = trimesh.proximity.closest_point(dst, points)
    return distance


def compare(a: trimesh.Trimesh, b: trimesh.Trimesh, samples: int = 20_000, seed: int = 0) -> dict:
    """Symmetric point-to-surface distances from surface samples, in mm.

    `hausdorff_mm` is the max over samples, so it slightly underestimates the true Hausdorff distance.
    """
    if len(a.faces) == 0 or len(b.faces) == 0:
        raise ValueError("cannot compare an empty mesh")
    ab = _one_way(a, b, samples, seed)
    ba = _one_way(b, a, samples, seed + 1)
    both = np.concatenate([ab, ba])
    return {
        "mean_mm": round(float(both.mean()), 5),
        "chamfer_mm": round(float((ab.mean() + ba.mean()) / 2), 5),
        "p95_mm": round(float(np.percentile(both, 95)), 5),
        "hausdorff_mm": round(float(both.max()), 5),
        "samples_per_direction": samples,
    }
