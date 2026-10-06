"""Cleanup and repair operations. Each takes a mesh and returns a new mesh plus a report;
inputs are never modified (M25 rule 1)."""

from __future__ import annotations

import numpy as np
import pymeshfix
import trimesh

from .analyze import boundary_loops, loop_perimeter


def remove_small_components(mesh: trimesh.Trimesh, min_faces: int = 50, min_extent_mm: float = 0.0,
                            keep_largest_only: bool = False) -> tuple[trimesh.Trimesh, dict]:
    parts = mesh.split(only_watertight=False)
    if not parts:
        return mesh.copy(), {"removed_components": 0, "kept_components": 0}
    if keep_largest_only:
        kept = [max(parts, key=lambda p: len(p.faces))]
    else:
        kept = [p for p in parts if len(p.faces) >= min_faces and float(p.extents.max()) >= min_extent_mm]
        if not kept:  # never return an empty mesh
            kept = [max(parts, key=lambda p: len(p.faces))]
    out = trimesh.util.concatenate(kept)
    return out, {"removed_components": len(parts) - len(kept), "kept_components": len(kept),
                 "removed_faces": int(len(mesh.faces) - len(out.faces))}


def fill_holes(mesh: trimesh.Trimesh, max_perimeter_mm: float = 50.0) -> tuple[trimesh.Trimesh, dict]:
    """Closes holes whose perimeter is ≤ `max_perimeter_mm` with a centroid fan.

    Larger openings are left alone on purpose — they are often real features (bores, slots).
    """
    m = mesh.copy()
    filled, skipped = 0, []
    new_vertices = [m.vertices]
    new_faces = [m.faces]
    next_index = len(m.vertices)
    edges = m.edges_sorted
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    boundary = {tuple(e) for e in unique[counts == 1]}
    # Directed boundary edges, in face winding order, to keep the fan oriented consistently.
    directed = [(a, b) for f in m.faces for a, b in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0]))
                if (min(a, b), max(a, b)) in boundary]
    for loop in boundary_loops(m):
        perimeter = loop_perimeter(m, loop)
        if perimeter > max_perimeter_mm:
            skipped.append(round(perimeter, 3))
            continue
        loop_set = set(loop.tolist())
        loop_edges = [(a, b) for a, b in directed if a in loop_set and b in loop_set]
        centroid = m.vertices[loop].mean(axis=0)
        new_vertices.append(centroid[None, :])
        # Reverse each boundary edge so the patch faces the same way as its neighbours.
        new_faces.append(np.array([[b, a, next_index] for a, b in loop_edges]))
        next_index += 1
        filled += 1
    out = trimesh.Trimesh(np.vstack(new_vertices), np.vstack(new_faces), process=True)
    return out, {"filled_holes": filled, "skipped_hole_perimeters_mm": skipped}


def fix_normals(mesh: trimesh.Trimesh) -> tuple[trimesh.Trimesh, dict]:
    m = mesh.copy()
    before = bool(m.is_winding_consistent), bool(m.is_watertight and m.volume < 0)
    trimesh.repair.fix_normals(m, multibody=True)
    return m, {"winding_was_consistent": before[0], "was_inverted": before[1],
               "winding_consistent": bool(m.is_winding_consistent)}


def repair_full(mesh: trimesh.Trimesh, join_components: bool = False) -> tuple[trimesh.Trimesh, dict]:
    """Robust watertight repair with MeshFix (removes self-intersections, fills all holes)."""
    v, f = pymeshfix.clean_from_arrays(np.asarray(mesh.vertices), np.asarray(mesh.faces),
                                       joincomp=join_components, remove_smallest_components=not join_components)
    out = trimesh.Trimesh(v, f, process=True)
    trimesh.repair.fix_normals(out)
    return out, {"watertight": bool(out.is_watertight), "faces_before": int(len(mesh.faces)),
                 "faces_after": int(len(out.faces))}


def decimate(mesh: trimesh.Trimesh, target_faces: int) -> tuple[trimesh.Trimesh, dict]:
    if target_faces >= len(mesh.faces):
        return mesh.copy(), {"faces_before": int(len(mesh.faces)), "faces_after": int(len(mesh.faces))}
    out = mesh.simplify_quadric_decimation(face_count=int(target_faces))
    return out, {"faces_before": int(len(mesh.faces)), "faces_after": int(len(out.faces))}
