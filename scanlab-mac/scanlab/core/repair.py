"""Cleanup and repair operations. Each takes a mesh and returns a new mesh plus a report;
inputs are never modified (M25 rule 1)."""

from __future__ import annotations

import numpy as np
import pymeshfix
import trimesh



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


def boundary_cycles(faces: np.ndarray) -> list[np.ndarray]:
    """Boundary edges (in face winding order) split into simple cycles.

    Walking directed edges keeps loops apart that touch at a single vertex ("figure-8" pinches,
    common in scans); treating them as one component would create non-manifold fans.
    """
    directed = np.stack([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]], axis=1).reshape(-1, 2)
    key = np.sort(directed, axis=1)
    _, inverse, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    boundary = directed[counts[inverse.ravel()] == 1]
    outgoing: dict[int, list[int]] = {}
    for i, (a, _) in enumerate(boundary):
        outgoing.setdefault(int(a), []).append(i)
    used = np.zeros(len(boundary), bool)
    cycles = []
    for start in range(len(boundary)):
        if used[start]:
            continue
        cycle, i = [], start
        while not used[i]:
            used[i] = True
            cycle.append(i)
            nxt = [j for j in outgoing.get(int(boundary[i, 1]), []) if not used[j]]
            if not nxt:
                break
            i = nxt[0]
        if len(cycle) >= 3 and boundary[cycle[-1], 1] == boundary[cycle[0], 0]:
            cycles.append(boundary[cycle])
    return cycles


def fill_holes(mesh: trimesh.Trimesh, max_perimeter_mm: float = 50.0) -> tuple[trimesh.Trimesh, dict]:
    """Closes holes whose perimeter is ≤ `max_perimeter_mm` with a centroid fan per boundary cycle.

    Larger openings are left alone on purpose — they are often real features (bores, slots).
    Vectorised where it matters: scanned meshes have millions of faces.
    """
    m = mesh.copy()
    new_vertices, new_faces = [m.vertices], [m.faces]
    next_index = len(m.vertices)
    filled, skipped = 0, []
    for edges in boundary_cycles(m.faces):
        perimeter = float(np.linalg.norm(m.vertices[edges[:, 0]] - m.vertices[edges[:, 1]], axis=1).sum())
        if perimeter > max_perimeter_mm:
            skipped.append(round(perimeter, 3))
            continue
        new_vertices.append(m.vertices[edges[:, 0]].mean(axis=0)[None, :])
        # Reverse each boundary edge so the patch faces the same way as its neighbours.
        new_faces.append(np.c_[edges[:, 1], edges[:, 0], np.full(len(edges), next_index)])
        next_index += 1
        filled += 1
    # No vertex merge: fan centres of different holes may coincide and must stay distinct.
    out = trimesh.Trimesh(np.vstack(new_vertices), np.vstack(new_faces), process=False)
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
    # MeshFix can silently discard most of a difficult mesh; never pass that off as a repair.
    if len(out.faces) < 0.5 * len(mesh.faces):
        raise ValueError(f"MeshFix kept only {len(out.faces)} of {len(mesh.faces)} faces; repair refused")
    trimesh.repair.fix_normals(out)
    return out, {"watertight": bool(out.is_watertight), "faces_before": int(len(mesh.faces)),
                 "faces_after": int(len(out.faces))}


def decimate(mesh: trimesh.Trimesh, target_faces: int) -> tuple[trimesh.Trimesh, dict]:
    if target_faces >= len(mesh.faces):
        return mesh.copy(), {"faces_before": int(len(mesh.faces)), "faces_after": int(len(mesh.faces))}
    out = mesh.simplify_quadric_decimation(face_count=int(target_faces))
    return out, {"faces_before": int(len(mesh.faces)), "faces_after": int(len(out.faces))}
