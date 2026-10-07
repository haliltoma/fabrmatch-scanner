"""Close a scanned part that rests on a table: its unseen bottom is the table.

Open loops near the table are classified by nesting (top view):
  outer loop                 → skirt straight down to z = 0, base on the table
  inner loop, table visible  → a through-opening (ring, frame): skirt to z = 0, hole in the base
  inner loop, floor visible  → an inner floor (open-top box): skirt to the observed floor height,
                               capped there facing up; the base underneath stays solid
The old centroid-fan cap turned ring openings into discs and box floors into holes.
"""

from __future__ import annotations

from collections.abc import Callable

import numpy as np
import trimesh
from shapely.geometry import Polygon

from ..core.repair import boundary_cycles

# Returns None when the table is visible through the ring (a hole), else the inner floor height (mm).
Classifier = Callable[[Polygon], float | None]


def _simple_ground_ring(xy: np.ndarray) -> np.ndarray:
    """Where the skirt meets the table. A scanned wall's bottom edge zig-zags in top view and its
    outline self-intersects; the ground points are new vertices, so smooth them along the loop with
    the smallest window that yields a simple polygon (order and overall shape are preserved)."""
    for window in (1, 3, 5, 9, 17, 33):
        if window == 1:
            ring = xy
        else:
            pad = window // 2
            ext = np.vstack([xy[-pad:], xy, xy[:pad]])
            kernel = np.ones(window) / window
            ring = np.c_[np.convolve(ext[:, 0], kernel, "valid"), np.convolve(ext[:, 1], kernel, "valid")]
        poly = Polygon(ring)
        if poly.is_valid and poly.area > 0:
            return ring
    raise ValueError("bottom loop projects to a self-intersecting outline even after smoothing")


def close_on_table(mesh: trimesh.Trimesh, band_mm: float,
                   classify: Classifier = lambda _: None) -> tuple[trimesh.Trimesh, dict]:
    """Returns the closed mesh and a report. Raises ValueError if the base cannot be built cleanly."""
    cycles = [c for c in boundary_cycles(mesh.faces) if mesh.vertices[c[:, 0], 2].max() <= band_mm]
    if not cycles:
        raise ValueError("no open loop near the table")
    rings, grounds = [], []
    for edges in cycles:
        xy = _simple_ground_ring(mesh.vertices[edges[:, 0], :2])
        grounds.append(xy)
        rings.append(Polygon(xy))

    order = sorted(range(len(rings)), key=lambda i: -rings[i].area)
    depth, parent = {}, {}
    for k, i in enumerate(order):
        containers = [j for j in order[:k] if rings[j].contains(rings[i].representative_point())]
        depth[i] = len(containers)
        parent[i] = containers[-1] if containers else None
    if max(depth.values()) > 1:
        raise ValueError("nested loops deeper than one level are not supported")
    floor = {i: classify(rings[i]) if depth[i] == 1 else None for i in order}

    vertices = [np.asarray(mesh.vertices, float)]
    faces = [np.asarray(mesh.faces)]
    n = len(mesh.vertices)

    def add_vertex(p: np.ndarray) -> int:
        nonlocal n
        vertices.append(p[None])
        n += 1
        return n - 1

    lowered: dict[int, dict[tuple, int]] = {}
    for i in order:
        z = floor[i] if floor[i] is not None else 0.0
        lut: dict[tuple, int] = {}
        ground_index = []
        for xy in grounds[i]:
            key = tuple(np.round(xy, 9))
            if key not in lut:
                lut[key] = add_vertex(np.r_[xy, z])
            ground_index.append(lut[key])
        k = len(cycles[i])
        for pos, (a, b) in enumerate(cycles[i]):
            a0, b0 = ground_index[pos], ground_index[(pos + 1) % k]
            faces.append(np.array([[b, a, a0], [b, a0, b0]]))
        lowered[i] = lut

    def cap(poly: Polygon, luts: list[dict[tuple, int]]) -> np.ndarray:
        tri_v, tri_f = trimesh.creation.triangulate_polygon(poly, engine="earcut")
        merged = {k: v for lut in luts for k, v in lut.items()}
        idx = []
        for xy in tri_v:
            key = tuple(np.round(xy, 9))
            if key not in merged:
                raise ValueError("triangulation introduced a vertex not on a skirt")
            idx.append(merged[key])
        return np.asarray(idx)[tri_f]

    caps = 0
    for i in order:
        if depth[i] == 0:  # base: outer ring minus through-openings
            holes = [j for j in order if parent[j] == i and floor[j] is None]
            tri = cap(Polygon(rings[i].exterior.coords, [rings[j].exterior.coords for j in holes]),
                      [lowered[i]] + [lowered[j] for j in holes])
        elif floor[i] is not None:  # inner floor
            tri = cap(rings[i], [lowered[i]])
        else:
            continue
        faces.append(tri)
        caps += len(tri)

    out = trimesh.Trimesh(np.vstack(vertices), np.vstack(faces), process=False)
    out.merge_vertices()
    out.update_faces(out.nondegenerate_faces())
    out.remove_unreferenced_vertices()
    trimesh.repair.fix_normals(out)  # consistent winding, outward
    return out, {"bottom_loops": len(cycles), "holes": sum(1 for i in order if depth[i] == 1 and floor[i] is None),
                 "floors": sum(1 for i in order if floor[i] is not None), "cap_faces": caps,
                 "watertight": bool(out.is_watertight)}
