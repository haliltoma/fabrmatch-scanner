import numpy as np
import pytest
import trimesh

from conftest import plate_with_bore, with_holes, write_inbox
from scanlab.core import orca, orient, printability
from scanlab.core.printer import list_profiles, load_profile

K2 = load_profile("creality_k2_pro")
PLA = K2.material("pla")


def test_k2_pro_profile_matches_orca_preset():
    assert "creality_k2_pro" in list_profiles()
    assert K2.build_volume_mm == (300, 300, 300) and K2.nozzle_mm == 0.4
    machine = orca.flatten_preset("machine", K2.orca_machine)
    assert machine["printable_area"] == ["0x0", "300x0", "300x300", "0x300"]
    assert machine["printable_height"] in ("300", 300)
    assert machine["nozzle_diameter"] == ["0.4"]
    for m in K2.materials.values():  # every material maps to a real Orca preset
        orca.flatten_preset("filament", m.orca_filament)


def test_unknown_printer_and_material_are_rejected():
    with pytest.raises(ValueError):
        load_profile("../../etc/passwd")
    with pytest.raises(ValueError):
        K2.material("wood")


def test_clean_plate_is_printable():
    report = printability.print_check(orient.place_on_bed(plate_with_bore()), K2, PLA)
    assert report["printable"], report["issues"]
    assert report["summary"]["bed_contact_mm2"] > 1000


def test_detects_open_mesh_oversize_and_thin_walls():
    holed = printability.print_check(orient.place_on_bed(with_holes(plate_with_bore(), 2)), K2, PLA)
    assert not holed["printable"] and "not_watertight" in {i["code"] for i in holed["issues"]}

    huge = printability.print_check(trimesh.creation.box((320, 100, 10)), K2, PLA)
    assert {"build_volume"} <= {i["code"] for i in huge["issues"]}

    thin = trimesh.creation.box((40, 40, 0.5))
    v, f = trimesh.remesh.subdivide_to_size(thin.vertices, thin.faces, max_edge=2)
    codes = {i["code"] for i in printability.print_check(trimesh.Trimesh(v, f), K2, PLA)["issues"]}
    assert "thin_walls" in codes


def test_t_shape_upside_down_has_overhangs_and_orientation_fixes_it():
    """A 'T' printed stem-down needs supports under the bar; flipped onto the bar it needs none."""
    bar = trimesh.creation.box((60, 20, 8)).apply_translation((0, 0, 24))
    stem = trimesh.creation.box((12, 20, 40))
    t = bar.union(stem, engine="manifold")
    placed = orient.place_on_bed(t)
    assert printability.overhang_faces(placed, 45).any()

    oriented, report = orient.optimize(t, 45)
    assert report["chosen"]["overhang_mm2"] < report["original"]["overhang_mm2"]
    assert report["chosen"]["overhang_mm2"] == 0
    assert oriented.bounds[0][2] == pytest.approx(0, abs=1e-6)
    # Rigid: shape (volume) is unchanged and the reported transform reproduces the result.
    assert oriented.volume == pytest.approx(t.volume, rel=1e-6)
    again = t.copy()
    again.apply_transform(np.array(report["rigid_transform"]))
    np.testing.assert_allclose(again.bounds, oriented.bounds, atol=1e-6)


def test_orientation_keeps_deviation_from_raw_at_zero(engine, ws):
    bar = trimesh.creation.box((60, 20, 8)).apply_translation((0, 0, 24))
    t = bar.union(trimesh.creation.box((12, 20, 40)), engine="manifold")
    raw, _ = engine.import_mesh(write_inbox(ws, t, "t.stl"))
    result = engine.orient_for_print(raw.project_id, max_deviation_mm=0.01)
    assert result.stored
    assert result.deviation_from_raw["p95_mm"] < 1e-3
    # A later non-rigid step on the rotated version is still measured against the raw scan correctly.
    follow = engine.fill_holes(raw.project_id, max_deviation_mm=0.01)
    assert follow.deviation_from_raw["p95_mm"] < 1e-3
    assert engine.compare(raw.project_id, raw.id, follow.version.id)["p95_mm"] < 1e-3


@pytest.mark.skipif(not orca.ORCA_BIN.exists(), reason="OrcaSlicer not installed")
def test_slice_dry_run_with_real_orcaslicer(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, plate_with_bore(), "plate.stl"))
    result = engine.slice_dry_run(raw.project_id, material="PETG", infill_pct=40)
    assert result["ok"] and result["printer"] == "Creality K2 Pro (0.4)" and result["material"] == "PETG"
    assert result["layers"] == 30  # 6 mm / 0.2 mm
    assert result["max_z_mm"] == pytest.approx(6.0)
    assert result["time_s"] > 0 and result["filament_g"] > 0
    assert result["settings"]["infill"] == "40%" and result["settings"]["xy_hole_compensation_mm"] == 0.1
    assert engine.store.events(raw.project_id)[-1]["kind"] == "slice_dry_run"


def test_gcode_stats_parser():
    g = "; estimated printing time (normal mode) = 1h 2m 3s\n; total filament used [g] = 12.5\n; total layer number: 40\n"
    s = orca.parse_gcode_stats(g)
    assert s["time_s"] == 3723 and s["filament_g"] == 12.5 and s["layers"] == 40


def _noisy(mesh, sigma=0.05, seed=2):
    v, f = trimesh.remesh.subdivide_to_size(mesh.vertices, mesh.faces, max_edge=1.5)
    m = trimesh.Trimesh(v, f, process=True)
    m.vertices += m.vertex_normals * np.random.default_rng(seed).normal(0, sigma, (len(m.vertices), 1))
    return orient.place_on_bed(m)


def test_rough_scanned_base_is_flagged_and_flattened():
    from scanlab.core import base
    shaft = trimesh.creation.cylinder(radius=10, height=40, sections=96)
    noisy = _noisy(shaft)
    codes = {i["code"] for i in printability.print_check(noisy, K2, PLA)["issues"]}
    assert "rough_base" in codes
    flat, report = base.flatten_base(noisy)
    assert 0.05 <= report["depth_mm"] <= 0.5
    assert report["flat_bed_area_after_mm2"] == pytest.approx(np.pi * 100, rel=0.05)
    assert flat.is_watertight and flat.bounds[0][2] == pytest.approx(0, abs=1e-9)
    assert "rough_base" not in {i["code"] for i in printability.print_check(flat, K2, PLA)["issues"]}


def test_flatten_base_rejects_absurd_depth():
    from scanlab.core import base
    with pytest.raises(ValueError):
        base.flatten_base(trimesh.creation.box((10, 10, 2)), depth_mm=5)


@pytest.mark.skipif(not orca.ORCA_BIN.exists(), reason="OrcaSlicer not installed")
def test_flattened_noisy_base_slices(tmp_path):
    """Benchmark finding: Orca may reject a spiky scanned base ("run found error"); a flattened one slices."""
    from scanlab.core import base
    noisy = _noisy(trimesh.creation.cylinder(radius=10, height=40, sections=96).apply_translation((0, 0, 20)))
    flat, _ = base.flatten_base(noisy)
    assert orca.slice_mesh(flat, K2, PLA, tmp_path)["ok"]


def test_flatten_base_deviation_counts_only_the_cut(engine, ws):
    """Regression: the drop back onto the bed is rigid and must not be charged as deviation."""
    noisy = _noisy(trimesh.creation.box((40, 30, 10)).apply_translation((0, 0, 5)))
    raw, _ = engine.import_mesh(write_inbox(ws, noisy, "b.ply"))
    r = engine.flatten_base(raw.project_id, depth_mm=0.3)
    assert r.report["height_lost_mm"] == pytest.approx(0.3, abs=0.02)
    # Only the bottom (≈ 1/4 of the surface) moves, by ≤ 0.3 mm; the p95 over the whole part stays small.
    assert r.deviation_from_raw["p95_mm"] < 0.3
    assert r.deviation_from_raw["mean_mm"] < 0.05
