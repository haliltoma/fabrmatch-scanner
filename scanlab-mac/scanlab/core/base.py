"""`print_flatten_base` (PRD M14 FR-14.4): cut a noisy scanned bottom flat so the first layer has area.

A scanned base is a field of spikes around ±3σ of sensor noise; slicers then see almost nothing at
the first layer height and refuse the part ("empty first layer"). Cutting at the noise band gives a
flat, capped face. Geometry above the cut is untouched.
"""

from __future__ import annotations

import numpy as np
import trimesh

from .orient import bed_translation, place_on_bed

MAX_AUTO_DEPTH_MM = 0.5


def estimate_base_noise(mesh: trimesh.Trimesh, band_mm: float = 1.0) -> float:
    """Spread of the bottom surface: z-range holding 95 % of the down-facing vertices near the bed."""
    z_min = mesh.bounds[0, 2]
    down = mesh.faces[mesh.face_normals[:, 2] < -0.9].ravel()
    z = mesh.vertices[np.unique(down), 2]
    z = z[z <= z_min + band_mm]
    if len(z) < 3:
        return 0.0
    return float(np.percentile(z, 95) - z_min)


def flatten_base(mesh: trimesh.Trimesh, depth_mm: float | None = None) -> tuple[trimesh.Trimesh, dict]:
    to_bed = bed_translation(mesh)
    m = mesh.copy()
    m.apply_transform(to_bed)
    noise = estimate_base_noise(m)
    depth = float(depth_mm) if depth_mm is not None else min(max(noise, 0.05), MAX_AUTO_DEPTH_MM)
    if depth <= 0:
        raise ValueError("depth_mm must be positive")
    if depth >= m.extents[2]:
        raise ValueError(f"depth {depth} mm would remove the whole part (height {m.extents[2]:.2f} mm)")
    big = float(m.extents.max()) * 4 + 10
    keep = trimesh.creation.box((big, big, big))
    keep.apply_translation((0, 0, depth + big / 2))
    cut = m.intersection(keep, engine="manifold")
    if len(cut.faces) == 0:
        raise ValueError("cut produced an empty mesh")
    flat_before = float(m.area_faces[(m.face_normals[:, 2] < -0.999) & (m.triangles[:, :, 2].max(axis=1) <= m.bounds[0, 2] + 0.05)].sum())
    drop = bed_translation(cut)
    out = cut.copy()
    out.apply_transform(drop)
    flat_after = float(out.area_faces[(out.face_normals[:, 2] < -0.999) & (out.triangles[:, :, 2].max(axis=1) <= 0.05)].sum())
    # Both moves are rigid; report them so deviation is measured on the cut alone, not on the shift.
    return out, {"rigid_transform": (drop @ to_bed).tolist(), "depth_mm": round(depth, 4), "estimated_base_noise_mm": round(noise, 4),
                 "flat_bed_area_before_mm2": round(flat_before, 1), "flat_bed_area_after_mm2": round(flat_after, 1),
                 "height_lost_mm": round(float(m.extents[2] - out.extents[2]), 4)}
