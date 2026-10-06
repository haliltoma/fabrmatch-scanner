"""`mesh_analyze` metrics (M25 analysis group, M14 FR-14.1 printability checks)."""

from __future__ import annotations

import numpy as np
import trimesh


def boundary_loops(mesh: trimesh.Trimesh) -> list[np.ndarray]:
    """Closed loops of boundary edges (edges used by exactly one face) — each one is a hole."""
    edges = mesh.edges_sorted
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    boundary = unique[counts == 1]
    if len(boundary) == 0:
        return []
    import networkx as nx

    g = nx.Graph()
    g.add_edges_from(boundary.tolist())
    return [np.array(list(c)) for c in nx.connected_components(g)]


def loop_perimeter(mesh: trimesh.Trimesh, loop_vertices: np.ndarray) -> float:
    """Total length of boundary edges whose both ends lie in the loop."""
    edges = mesh.edges_sorted
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    b = unique[counts == 1]
    mask = np.isin(b[:, 0], loop_vertices) & np.isin(b[:, 1], loop_vertices)
    seg = mesh.vertices[b[mask]]
    return float(np.linalg.norm(seg[:, 0] - seg[:, 1], axis=1).sum())


def wall_thickness(mesh: trimesh.Trimesh, samples: int = 400, seed: int = 0,
                   noise_floor_mm: float = 0.1) -> dict | None:
    """Estimates wall thickness by casting rays inward from surface samples (watertight meshes only).

    Scanned surfaces are noisy: a ray along a jittered face normal often clips the neighbouring
    face and reports ~0 mm. So the direction is the smoothed (vertex-averaged) normal, rays start
    `noise_floor_mm` inside the surface, and only hits on the opposite skin count.
    """
    if not mesh.is_watertight or len(mesh.faces) == 0:
        return None
    rng = np.random.default_rng(seed)
    points, face_idx = trimesh.sample.sample_surface(mesh, samples, seed=rng)
    smooth = mesh.vertex_normals[mesh.faces[face_idx]].mean(axis=1)
    smooth /= np.linalg.norm(smooth, axis=1, keepdims=True)
    origins = points - smooth * noise_floor_mm
    locations, ray_idx, tri_idx = mesh.ray.intersects_location(origins, -smooth, multiple_hits=False)
    # Only hits on the opposite skin (normals roughly anti-parallel); rays near an edge otherwise
    # hit the adjacent perpendicular face and report a false "thin wall".
    opposite = np.einsum("ij,ij->i", mesh.face_normals[tri_idx], smooth[ray_idx]) < -0.7
    if not opposite.any():
        return None
    d = np.linalg.norm(locations[opposite] - origins[ray_idx[opposite]], axis=1) + noise_floor_mm
    return {"min_mm": float(d.min()), "p5_mm": float(np.percentile(d, 5)), "median_mm": float(np.median(d)),
            "samples": int(len(d)), "noise_floor_mm": noise_floor_mm}


def analyze(mesh: trimesh.Trimesh, thickness_samples: int = 400) -> dict:
    edges = mesh.edges_sorted
    _, counts = np.unique(edges, axis=0, return_counts=True)
    components = mesh.split(only_watertight=False)
    loops = boundary_loops(mesh)
    bounds = mesh.bounds if len(mesh.vertices) else np.zeros((2, 3))
    degenerate = int(len(mesh.faces) - int(mesh.nondegenerate_faces().sum()))
    watertight = bool(mesh.is_watertight)
    return {
        "unit": "mm",
        "vertices": int(len(mesh.vertices)),
        "triangles": int(len(mesh.faces)),
        "bbox_min": bounds[0].round(4).tolist(),
        "bbox_size": (bounds[1] - bounds[0]).round(4).tolist(),
        "surface_area_mm2": round(float(mesh.area), 4),
        "volume_mm3": round(float(mesh.volume), 4) if watertight else None,
        "watertight": watertight,
        "manifold": bool((counts <= 2).all()),
        "non_manifold_edges": int((counts > 2).sum()),
        "boundary_edges": int((counts == 1).sum()),
        "holes": len(loops),
        "winding_consistent": bool(mesh.is_winding_consistent),
        "inward_normals": bool(watertight and mesh.volume < 0),
        "components": len(components),
        "largest_component_share": round(max((len(c.faces) for c in components), default=0) / max(len(mesh.faces), 1), 4),
        "degenerate_faces": degenerate,
        "duplicate_faces": int(len(mesh.faces) - len(np.unique(np.sort(mesh.faces, axis=1), axis=0))),
        "wall_thickness": wall_thickness(mesh, thickness_samples),
        "self_intersections": "not_computed",
    }
