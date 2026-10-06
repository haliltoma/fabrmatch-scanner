from pathlib import Path

import numpy as np
import pytest
import trimesh

from scanlab.core.engine import Engine
from scanlab.core.workspace import Workspace

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"


@pytest.fixture
def ws(tmp_path) -> Workspace:
    return Workspace.create(tmp_path / "home")


@pytest.fixture
def engine(ws) -> Engine:
    return Engine(ws)


def plate_with_bore() -> trimesh.Trimesh:
    """40×30×6 mm plate with a Ø8 mm through hole, remeshed to ~3 mm edges like a dense scan."""
    plate = trimesh.creation.box((40, 30, 6))
    bore = trimesh.creation.cylinder(radius=4, height=10, sections=48)
    cad = plate.difference(bore, engine="manifold")
    v, f = trimesh.remesh.subdivide_to_size(cad.vertices, cad.faces, max_edge=3.0)
    return trimesh.Trimesh(v, f, process=True)


def with_holes(mesh: trimesh.Trimesh, n: int, seed: int = 1) -> trimesh.Trimesh:
    """Deletes `n` faces sharing no vertex with each other, giving `n` separate holes (scan dropouts)."""
    rng = np.random.default_rng(seed)
    used: set[int] = set()
    chosen: list[int] = []
    for f in rng.permutation(len(mesh.faces)):
        verts = set(mesh.faces[f].tolist())
        if verts & used:
            continue
        # Also skip neighbours of used vertices so the two boundaries never touch.
        ring = set(mesh.faces[np.isin(mesh.faces, list(verts)).any(axis=1)].ravel().tolist())
        if ring & used:
            continue
        chosen.append(int(f))
        used |= ring
        if len(chosen) == n:
            break
    assert len(chosen) == n, "mesh too small for the requested number of holes"
    keep = np.ones(len(mesh.faces), bool)
    keep[chosen] = False
    return trimesh.Trimesh(mesh.vertices, mesh.faces[keep], process=False)


def with_debris(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    """Adds two small floating fragments, like background clutter in a scan."""
    bits = [trimesh.creation.icosphere(1, radius=0.8).apply_translation(p) for p in ((60, 0, 0), (0, 50, 10))]
    return trimesh.util.concatenate([mesh, *bits])


def write_inbox(ws: Workspace, mesh: trimesh.Trimesh, name: str) -> str:
    mesh.export(ws.inbox / name)
    return name
