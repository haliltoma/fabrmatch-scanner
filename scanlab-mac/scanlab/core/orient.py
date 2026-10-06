"""`print_orient_optimize`: pick a bed orientation that minimises supports and maximises bed contact
(PRD §2.1 "yön optimizasyonu")."""

from __future__ import annotations

import numpy as np
import trimesh

from .printability import bed_contact_area, overhang_faces


def rotation_to_down(normal: np.ndarray) -> np.ndarray:
    """4×4 rotation taking `normal` to −Z."""
    return trimesh.geometry.align_vectors(normal / np.linalg.norm(normal), [0, 0, -1])


def bed_translation(mesh: trimesh.Trimesh) -> np.ndarray:
    """4×4 translation resting the mesh on z = 0, centred on the origin in XY."""
    lo, hi = mesh.bounds
    return trimesh.transformations.translation_matrix([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])


def place_on_bed(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    m = mesh.copy()
    m.apply_transform(bed_translation(m))
    return m


def candidate_normals(mesh: trimesh.Trimesh, hull_facets: int = 8) -> list[np.ndarray]:
    axes = [np.array(v, float) for v in ((0, 0, -1), (0, 0, 1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0))]
    hull = mesh.convex_hull
    order = np.argsort(hull.facets_area)[::-1][:hull_facets]
    facets = [hull.facets_normal[i] for i in order]
    out: list[np.ndarray] = []
    for n in axes + facets:
        if not any(np.dot(n, o) > 0.999 for o in out):
            out.append(n)
    return out


def score(mesh: trimesh.Trimesh, overhang_angle_deg: float, bed_tolerance_mm: float = 0.4) -> dict:
    over = float(mesh.area_faces[overhang_faces(mesh, overhang_angle_deg, bed_tolerance_mm)].sum())
    contact = bed_contact_area(mesh, bed_tolerance_mm)
    height = float(mesh.extents[2])
    # Supports dominate print quality on functional parts; height costs time; contact helps adhesion.
    cost = over / max(mesh.area, 1e-9) * 100 + height / max(mesh.extents.max(), 1e-9) * 10 - min(contact, 400) / 40
    return {"overhang_mm2": round(over, 1), "bed_contact_mm2": round(contact, 1), "height_mm": round(height, 2),
            "cost": round(cost, 3)}


def optimize(mesh: trimesh.Trimesh, overhang_angle_deg: float, top_k: int = 3,
             bed_tolerance_mm: float = 0.4) -> tuple[trimesh.Trimesh, dict]:
    ranked = []
    for n in candidate_normals(mesh):
        rotated = mesh.copy()
        rotated.apply_transform(rotation_to_down(n))
        ranked.append((score(place_on_bed(rotated), overhang_angle_deg, bed_tolerance_mm), n, rotated))
    ranked.sort(key=lambda r: r[0]["cost"])
    best_score, best_normal, best_mesh = ranked[0]
    original = score(place_on_bed(mesh), overhang_angle_deg, bed_tolerance_mm)
    transform = bed_translation(best_mesh) @ rotation_to_down(best_normal)
    placed = mesh.copy()
    placed.apply_transform(transform)
    return placed, {
        "rigid_transform": np.round(transform, 9).tolist(),
        "chosen_down_normal": np.round(best_normal, 4).tolist(), "chosen": best_score, "original": original,
        "alternatives": [{"down_normal": np.round(n, 4).tolist(), **s} for s, n, _ in ranked[1:top_k]],
    }
