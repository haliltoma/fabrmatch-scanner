import pytest

from scanlab.core.workspace import PathNotAllowed


def test_relative_paths_resolve_into_inbox(ws):
    (ws.inbox / "a.stl").write_bytes(b"x")
    assert ws.resolve_input("a.stl") == ws.inbox / "a.stl"


@pytest.mark.parametrize("bad", ["../../../../../../../../etc/passwd", "/etc/hosts"])
def test_rejects_paths_outside_roots(ws, bad):
    with pytest.raises(PathNotAllowed):
        ws.resolve_input(bad)


def test_rejects_symlink_escape(ws, tmp_path):
    outside = tmp_path / "secret.stl"
    outside.write_bytes(b"x")
    (ws.inbox / "link.stl").symlink_to(outside)
    with pytest.raises(PathNotAllowed):
        ws.resolve_input("link.stl")


@pytest.mark.parametrize("bad", ["../x.stl", "sub/x.stl", ".hidden.stl", ""])
def test_output_must_be_plain_name(ws, bad):
    with pytest.raises(PathNotAllowed):
        ws.resolve_output(bad)
