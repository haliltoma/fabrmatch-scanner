import numpy as np
import pytest
import trimesh

from scanlab.core import repair
from scanlab.recon import pipeline as P
from scanlab.recon.capture import Capture, CaptureFormatError, DepthFrame
from scanlab.recon.simulate import LIDAR, TRUEDEPTH, orbit_poses, placed_truth, simulate_capture


def block():
    return trimesh.creation.box((40, 30, 12))


@pytest.fixture(scope="module")
def td_capture():
    cap, true_poses = simulate_capture(block(), TRUEDEPTH, seed=3, per_ring=8)
    return cap, true_poses


def test_sldf_round_trip(tmp_path, td_capture):
    cap, _ = td_capture
    f = cap.frames[0]
    g = DepthFrame.decode(f.encode())
    np.testing.assert_array_equal(g.depth, f.depth)
    np.testing.assert_array_equal(g.confidence, f.confidence)
    np.testing.assert_allclose(g.pose, f.pose, atol=1e-6)
    cap.save(tmp_path)
    again = Capture.load(tmp_path)
    assert again.sensor == "truedepth" and len(again.frames) == len(cap.frames)


@pytest.mark.parametrize("cut", [0, 10, 100])
def test_sldf_truncated(td_capture, cut):
    with pytest.raises(CaptureFormatError):
        DepthFrame.decode(td_capture[0].frames[0].encode()[:cut])


def test_capture_rejects_path_escape(tmp_path, td_capture):
    td_capture[0].save(tmp_path)
    (tmp_path / "capture.json").write_text('{"format":"scanlab-capture","version":1,"frames":["../../x.sldf"]}')
    with pytest.raises(CaptureFormatError):
        Capture.load(tmp_path)


def test_back_projection_lands_on_the_part(td_capture):
    cap, _ = td_capture
    truth = placed_truth(block())
    pts = np.vstack([f.points(2)[0] for f in cap.frames[:4]]) * 1000
    on_part = pts[(np.abs(pts[:, 0]) < 19) & (np.abs(pts[:, 1]) < 14) & (pts[:, 2] > 3)]
    d = P._surface_distance(truth, on_part)
    # Noise grows at grazing angles (the top face is seen from 20° elevation); a convention bug
    # (axis flip, wrong intrinsics) would put points tens of millimetres away.
    assert np.median(d) < 1.5


def test_focus_point_is_the_orbit_centre():
    centre = np.array([0.1, -0.2, 0.05])
    frames = [DepthFrame(np.zeros((2, 2), np.float32), np.zeros((2, 2), np.uint8), 1, 1, 1, 1, p)
              for p in orbit_poses(centre, 0.3, per_ring=6)]
    np.testing.assert_allclose(P.focus_point(frames), centre, atol=1e-6)


def test_scene_finds_part_not_table(td_capture):
    cap, _ = td_capture
    scene = P.prepare_scene(cap, P.CONFIGS["truedepth"])
    size = scene.roi_max - scene.roi_min
    assert 40 <= size[0] <= 50 and 30 <= size[1] <= 40  # part + pad + noise, not the 1.2 m table
    assert scene.config.margin_mm >= P.CONFIGS["truedepth"].margin_mm


def test_reconstruction_end_to_end(td_capture):
    """TSDF→Poisson is the robust closer (benchmark winner); plain TSDF must at least close."""
    cap, _ = td_capture
    scene = P.prepare_scene(cap, P.CONFIGS["truedepth"])
    truth = placed_truth(block())
    hybrid = P.finalize(P.tsdf_poisson(scene, 1.0), scene)
    assert hybrid.is_watertight
    assert P.truth_score(hybrid, truth, 0.5)["f"] > 0.85
    assert hybrid.volume == pytest.approx(truth.volume, rel=0.05)
    assert P.finalize(P.tsdf(scene, 1.0), scene).is_watertight


def test_lidar_preset_is_coarser_than_truedepth():
    assert LIDAR.width * LIDAR.height < TRUEDEPTH.width * TRUEDEPTH.height
    assert LIDAR.sigma(np.array(0.4)) > TRUEDEPTH.sigma(np.array(0.28))


def test_fill_holes_handles_figure_eight_pinch():
    """Regression: two holes touching at one vertex were fanned as one loop → non-manifold edges."""
    m = trimesh.creation.icosphere(3)
    v = 0
    ring = np.where(np.isin(m.faces, v).any(axis=1))[0]
    a, b = ring[0], [f for f in ring if not set(m.faces[f]) & (set(m.faces[ring[0]]) - {v})][0]
    holed = trimesh.Trimesh(m.vertices, np.delete(m.faces, [a, b], axis=0), process=False)
    assert len(repair.boundary_cycles(holed.faces)) == 2
    filled, report = repair.fill_holes(holed, 1e9)
    assert report["filled_holes"] == 2 and filled.is_watertight


def test_meshfix_guard_refuses_destroyed_output():
    soup = trimesh.Trimesh(np.random.default_rng(0).random((300, 3)), np.random.default_rng(1).integers(0, 300, (100, 3)))
    with pytest.raises(ValueError, match="refused"):
        repair.repair_full(soup)


def test_pick_best_reports_when_everything_failed():
    with pytest.raises(ValueError, match="every reconstruction algorithm failed"):
        P.pick_best([P.Candidate("x", None, 0.0, error="boom")])


def test_engine_reconstruct_keeps_all_candidates_and_heads_the_best(engine, ws, td_capture):
    td_capture[0].save(ws.inbox / "scan1")
    result = engine.reconstruct(["scan1"], "Blok", algorithms=["tsdf_1mm", "tsdf_2mm", "poisson_d8"])
    pid = result["project_id"]
    versions = engine.store.versions(pid)
    assert {v.tool for v in versions} == {"reconstruct:tsdf_1mm", "reconstruct:tsdf_2mm", "reconstruct:poisson_d8"}
    assert engine.store.head(pid).id == result["chosen_version_id"] == versions[0].id  # best is the reference
    assert result["chosen"] in {r["algorithm"] for r in result["ranking"]}
    assert engine.analyze(pid)["watertight"]


def test_ring_base_is_annular_not_a_disc():
    """Regression: a ring resting on the table must keep its hole when the unseen base is closed."""
    from scanlab.recon.closure import close_on_table
    ring = trimesh.creation.annulus(r_min=10, r_max=20, height=8, sections=64)
    ring.apply_translation((0, 0, 4))
    # Simulate an unseen base: drop every face below z = 1.
    keep = ring.triangles_center[:, 2] > 1
    open_ring = trimesh.Trimesh(ring.vertices, ring.faces[keep], process=True)
    assert not open_ring.is_watertight
    closed, report = close_on_table(open_ring, band_mm=1)
    assert report["bottom_loops"] == 2 and closed.is_watertight
    assert closed.volume == pytest.approx(ring.volume, rel=0.02)
    assert not closed.contains([[0, 0, 4]])[0]  # the hole stays a hole


def test_open_top_box_keeps_its_floor():
    """Regression: an inner floor near table height must not be cut out like the hole of a ring."""
    from scanlab.recon.closure import close_on_table
    ring = trimesh.creation.annulus(r_min=10, r_max=20, height=8, sections=64).apply_translation((0, 0, 4))
    keep = ring.triangles_center[:, 2] > 1
    open_ring = trimesh.Trimesh(ring.vertices, ring.faces[keep], process=True)
    closed, report = close_on_table(open_ring, band_mm=1, classify=lambda _: 0.6)
    assert report["floors"] == 1 and closed.is_watertight
    inside = closed.contains([[0, 0, 0.3], [0, 0, 4], [15, 0, 4]])
    assert inside.tolist() == [True, False, True]  # solid floor under the cavity, cavity open above
