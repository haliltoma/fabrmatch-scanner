import numpy as np
import pytest
import trimesh

from scanlab.recon import multipass as M
from scanlab.recon import pipeline as P
from scanlab.recon.simulate import TRUEDEPTH, flipped_pass, placed_truth, simulate_capture


def l_block():
    """An asymmetric part (L-shaped) so registration has a unique answer."""
    a = trimesh.creation.box((40, 24, 8)).apply_translation((0, 0, 4))
    b = trimesh.creation.box((10, 24, 20)).apply_translation((15, 0, 10))
    return placed_truth(a.union(b, engine="manifold"))


@pytest.fixture(scope="module")
def passes():
    a = l_block()
    b, t_true = flipped_pass(a, yaw_deg=50)
    cap_a, _ = simulate_capture(a, TRUEDEPTH, seed=11, per_ring=8)
    cap_b, _ = simulate_capture(b, TRUEDEPTH, seed=12, per_ring=8)
    cfg = P.CONFIGS["truedepth"]
    return a, b, t_true, P.prepare_scene(cap_a, cfg), P.prepare_scene(cap_b, cfg)


def test_flipped_pass_truth_transform_is_consistent():
    a = l_block()
    b, t = flipped_pass(a, yaw_deg=20)
    back = b.copy()
    back.apply_transform(t)
    np.testing.assert_allclose(back.bounds, a.bounds, atol=1e-6)
    assert t[2, 2] == pytest.approx(-1)  # turned over
    assert b.bounds[0][2] == pytest.approx(0, abs=1e-9)  # resting on the table


def test_registration_recovers_the_flip(passes):
    a, b, _, sa, sb = passes
    r = M.register(sb, sa)
    aligned = b.copy()
    aligned.apply_transform(r.transform)
    assert P.truth_score(aligned, a, 0.5)["chamfer_mm"] < 0.4
    assert M.turned_over(r.transform)


def test_free_space_is_near_zero_for_own_points(passes):
    *_, sa, _ = passes
    pts, _ = M.part_points(sa)
    assert P.free_space_rate(pts[::40], sa, 3 * sa.config.tau_mm) < 0.02


def test_normal_aware_icp_does_not_glue_opposite_faces():
    """Regression: plain ICP matched a thin plate's top in one pass to its bottom in the other."""
    rng = np.random.default_rng(0)
    xy = rng.uniform(-20, 20, (4000, 2))
    top = np.c_[xy, np.full(len(xy), 3.0)]
    bottom = np.c_[xy, np.zeros(len(xy))]
    up, down = np.tile([0, 0, 1.0], (len(xy), 1)), np.tile([0, 0, -1.0], (len(xy), 1))
    # Target saw the top; source saw the bottom, slightly misplaced (0.5 mm high).
    dst = np.vstack([top, bottom[:200]])
    dst_n = np.vstack([up, down[:200]])
    t0 = np.eye(4)
    t0[2, 3] = 0.5
    t, fit, _ = M.icp_normal_aware(bottom, down, dst, dst_n, t0, (4.0, 2.0, 1.0))
    assert abs(t[2, 3]) < 0.2  # stays on the bottom face, not pulled 3 mm up onto the top


def test_contact_offset_finds_the_resting_face(passes):
    a, b, t_true, _, sb = passes
    pts, cams = M.part_points(sb)
    cloud = M._cloud(pts, cams, 0.8)
    dz = M.contact_offset(t_true, np.asarray(cloud.points), np.asarray(cloud.normals))
    assert dz is not None and abs(dz) < 0.4


def test_merge_expresses_both_passes_in_the_first_table_frame(passes):
    a, _, t_true, sa, sb = passes
    merged = M.merge([sa, sb], [np.eye(4), t_true])
    assert not merged.table_closure
    d = P._surface_distance(a, merged.train_points[::30])
    assert np.median(d) < 0.6  # both passes' points land on the part
    # The underside (z ≈ 0) is now observed.
    assert (merged.train_points[:, 2] < 1.0).sum() > 1000


def test_unturned_second_pass_is_reported():
    a = l_block()
    cap_a, _ = simulate_capture(a, TRUEDEPTH, seed=21, per_ring=6)
    cap_b, _ = simulate_capture(a, TRUEDEPTH, seed=22, per_ring=6)  # not turned
    cfg = P.CONFIGS["truedepth"]
    with pytest.raises(ValueError, match="turned"):
        M.register(P.prepare_scene(cap_b, cfg), P.prepare_scene(cap_a, cfg))
