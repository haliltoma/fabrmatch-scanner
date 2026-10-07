import numpy as np
import pytest

from conftest import plate_with_bore, with_debris, with_holes
from scanlab.core import analyze, repair


def test_clean_part_metrics():
    m = analyze.analyze(plate_with_bore())
    assert m["watertight"] and m["manifold"] and m["holes"] == 0 and m["components"] == 1
    assert m["bbox_size"] == pytest.approx([40, 30, 6], abs=1e-3)
    assert m["volume_mm3"] == pytest.approx(40 * 30 * 6 - np.pi * 16 * 6, rel=0.01)
    # Thickness rays hit the opposite skin: the plate is 6 mm thick.
    assert m["wall_thickness"]["median_mm"] == pytest.approx(6, abs=0.5)


def test_detects_holes_and_debris():
    m = analyze.analyze(with_debris(with_holes(plate_with_bore(), 3)))
    assert not m["watertight"]
    assert m["holes"] == 3
    assert m["components"] == 3
    assert m["volume_mm3"] is None


def test_fill_holes_closes_small_dropouts_only():
    holed = with_holes(plate_with_bore(), 3)
    filled, report = repair.fill_holes(holed, max_perimeter_mm=200)
    assert report["filled_holes"] == 3
    m = analyze.analyze(filled)
    assert m["watertight"] and m["holes"] == 0 and m["winding_consistent"]

    _, strict = repair.fill_holes(holed, max_perimeter_mm=1e-6)
    assert strict["filled_holes"] == 0 and len(strict["skipped_hole_perimeters_mm"]) == 3


def test_remove_small_components():
    out, report = repair.remove_small_components(with_debris(plate_with_bore()), min_faces=100)
    assert report["removed_components"] == 2
    assert analyze.analyze(out)["components"] == 1


def test_repair_full_makes_watertight():
    out, report = repair.repair_full(with_holes(plate_with_bore(), 5))
    assert report["watertight"]
    assert analyze.analyze(out)["holes"] == 0


def test_fix_normals_reverts_inversion():
    m = plate_with_bore()
    m.invert()
    assert analyze.analyze(m)["inward_normals"]
    out, report = repair.fix_normals(m)
    assert report["was_inverted"]
    assert not analyze.analyze(out)["inward_normals"]


def test_wall_thickness_ignores_degenerate_normals():
    """Regression: samples whose vertex normals cancel out produced NaN rays and crashed rtree."""
    import trimesh
    box = trimesh.creation.box((10, 10, 10))
    # A zero-area sliver whose vertex normals cancel, glued onto a watertight box.
    m = box.copy()
    m.vertex_normals  # noqa: B018 — force computation
    sliver = trimesh.Trimesh(m.vertices, np.vstack([m.faces, [[0, 0, 1]]]), process=False)
    assert analyze.wall_thickness(box) is not None
    analyze.wall_thickness(sliver)  # must not raise
