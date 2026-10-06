"""PRD M26 acceptance parts as synthetic scans: CAD truth + scan noise + dropouts + debris.

Each part is (name, truth, scan). The truth mesh is what a perfect scan would give; agent and
baseline results are measured against it, not just against the noisy scan.
"""

from __future__ import annotations

import numpy as np
import trimesh


def _dense(mesh: trimesh.Trimesh, edge: float) -> trimesh.Trimesh:
    v, f = trimesh.remesh.subdivide_to_size(mesh.vertices, mesh.faces, max_edge=edge)
    return trimesh.Trimesh(v, f, process=True)


def flat_plate() -> trimesh.Trimesh:
    return trimesh.creation.box((80, 50, 4))


def holed_bracket() -> trimesh.Trimesh:
    """L bracket 60×40×30, 5 mm thick, two Ø6.5 bolt holes in the base and one in the upright."""
    base = trimesh.creation.box((60, 40, 5)).apply_translation((0, 0, 2.5))
    upright = trimesh.creation.box((60, 5, 30)).apply_translation((0, 17.5, 15))
    body = base.union(upright, engine="manifold")
    cut = [trimesh.creation.cylinder(radius=3.25, height=20, sections=48).apply_translation((x, -5, 2.5))
           for x in (-18, 18)]
    side = trimesh.creation.cylinder(radius=3.25, height=20, sections=48)
    side.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
    side.apply_translation((0, 17.5, 20))
    return body.difference(trimesh.util.concatenate([*cut, side]), engine="manifold")


def stepped_shaft() -> trimesh.Trimesh:
    """Ø20 × 40 shaft with a Ø12 × 25 journal (lying along Z)."""
    a = trimesh.creation.cylinder(radius=10, height=40, sections=96).apply_translation((0, 0, 20))
    b = trimesh.creation.cylinder(radius=6, height=25, sections=96).apply_translation((0, 0, 52.5))
    return a.union(b, engine="manifold")


def thin_walled_box() -> trimesh.Trimesh:
    """50×40×30 open-top box, 1.2 mm walls and floor."""
    outer = trimesh.creation.box((50, 40, 30)).apply_translation((0, 0, 15))
    inner = trimesh.creation.box((47.6, 37.6, 30)).apply_translation((0, 0, 16.2))
    return outer.difference(inner, engine="manifold")


def organic_handle() -> trimesh.Trimesh:
    """Curved grip: a torus segment-like ellipsoidal ring."""
    t = trimesh.creation.torus(major_radius=30, minor_radius=8, major_sections=96, minor_sections=32)
    t.apply_scale((1.0, 0.6, 1.0))
    return t


PARTS = {"flat_plate": flat_plate, "holed_bracket": holed_bracket, "stepped_shaft": stepped_shaft,
         "thin_walled_box": thin_walled_box, "organic_handle": organic_handle}


def make_scan(truth: trimesh.Trimesh, seed: int, noise_mm: float = 0.05, dropouts: int = 4,
              edge_mm: float = 1.5) -> trimesh.Trimesh:
    rng = np.random.default_rng(seed)
    m = _dense(truth, edge_mm)
    m.vertices += m.vertex_normals * rng.normal(0, noise_mm, (len(m.vertices), 1))
    # Dropouts: delete small patches (a face and its neighbours) at separated places.
    keep = np.ones(len(m.faces), bool)
    used: set[int] = set()
    for f in rng.permutation(len(m.faces)):
        if dropouts == 0:
            break
        patch = np.where(np.isin(m.faces, m.faces[f]).any(axis=1))[0]
        ring = set(m.faces[patch].ravel().tolist())
        if ring & used:
            continue
        keep[patch] = False
        used |= set(m.faces[np.isin(m.faces, list(ring)).any(axis=1)].ravel().tolist())
        dropouts -= 1
    m = trimesh.Trimesh(m.vertices, m.faces[keep], process=False)
    m.remove_unreferenced_vertices()
    debris = [trimesh.creation.icosphere(1, radius=r).apply_translation(p)
              for r, p in ((0.7, truth.bounds[1] + 15), (1.0, truth.bounds[0] - 12))]
    return trimesh.util.concatenate([m, *debris])
