import pytest

from conftest import plate_with_bore, with_debris, with_holes, write_inbox
from scanlab.core.engine import DeviationBudgetExceeded


def test_import_creates_raw_version(engine, ws):
    v, metrics = engine.import_mesh(write_inbox(ws, plate_with_bore(), "part.stl"))
    assert v.tool == "import" and v.parent_id is None
    assert metrics["watertight"]
    assert engine.store.head(v.project_id).id == v.id


def test_analyze_repair_analyze_chain_is_versioned(engine, ws):
    """M25 acceptance: mesh_analyze → mesh_repair → mesh_analyze, recorded in the version history."""
    raw, _ = engine.import_mesh(write_inbox(ws, with_debris(with_holes(plate_with_bore(), 4)), "scan.ply"))
    pid = raw.project_id
    assert engine.analyze(pid)["holes"] == 4

    cleaned = engine.remove_small_components(pid, min_faces=100)
    filled = engine.fill_holes(pid, max_perimeter_mm=200)
    after = engine.analyze(pid)

    assert after["watertight"] and after["components"] == 1
    history = engine.store.versions(pid)
    assert [v.tool for v in history] == ["import", "mesh_remove_small_components", "mesh_fill_holes"]
    assert history[2].parent_id == cleaned.version.id
    assert filled.deviation_from_raw["p95_mm"] < 0.5
    assert raw.file.exists()  # original never overwritten


def test_dry_run_does_not_store(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, with_holes(plate_with_bore(), 2), "s.stl"))
    result = engine.fill_holes(raw.project_id, dry_run=True)
    assert not result.stored and result.metrics["holes"] == 0
    assert len(engine.store.versions(raw.project_id)) == 1


def test_deviation_budget_rejects_aggressive_decimation(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, plate_with_bore(), "p.stl"))
    with pytest.raises(DeviationBudgetExceeded):
        engine.decimate(raw.project_id, target_faces=12, max_deviation_mm=0.01)
    assert len(engine.store.versions(raw.project_id)) == 1
    assert engine.store.events(raw.project_id)[-1]["kind"] == "rejected"


def test_revert_moves_head(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, with_holes(plate_with_bore(), 2), "s.stl"))
    engine.fill_holes(raw.project_id)
    engine.store.revert(raw.project_id, raw.id)
    assert engine.store.head(raw.project_id).id == raw.id
    assert engine.analyze(raw.project_id)["holes"] == 2


@pytest.mark.parametrize("fmt", ["stl", "ply", "obj", "glb", "3mf"])
def test_export_formats_round_trip(engine, ws, fmt):
    raw, _ = engine.import_mesh(write_inbox(ws, plate_with_bore(), "p.stl"))
    result = engine.export(raw.project_id, f"part.{fmt}")
    assert (ws.outbox / f"part.{fmt}").exists()
    assert result["verified_triangles"] == result["triangles"]


def test_render_returns_pngs(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, plate_with_bore(), "p.stl"))
    images = engine.render(raw.project_id, views=["iso", "top"], size_px=200)
    assert [n for n, _ in images] == ["iso", "top"]
    assert all(png.startswith(b"\x89PNG") for _, png in images)


def test_report_lists_history(engine, ws):
    raw, _ = engine.import_mesh(write_inbox(ws, with_holes(plate_with_bore(), 2), "s.stl"))
    engine.fill_holes(raw.project_id)
    md = engine.report_markdown(raw.project_id)
    assert "mesh_fill_holes" in md and raw.id in md
