"""Drives the MCP server in-process through `call_tool`, the same entry point a client hits."""

import json

import pytest

from conftest import plate_with_bore, with_debris, with_holes, write_inbox
from mcp.server.mcpserver.exceptions import ToolError

from scanlab.mcp_server import server


@pytest.fixture(autouse=True)
def isolated_engine(engine, monkeypatch):
    monkeypatch.setattr(server, "_engine", engine)
    return engine


def _text(result) -> str:
    return result.content[0].text


async def call(name, **args):
    return await server.mcp.call_tool(name, args)


async def test_tool_catalog_has_no_code_execution():
    names = {t.name for t in await server.mcp.list_tools()}
    assert {"mesh_import", "mesh_analyze", "mesh_render_views", "mesh_repair", "mesh_fill_holes",
            "deviation_compare", "export_asset", "version_revert"} <= names
    assert not any("exec" in n or "code" in n or "python" in n for n in names)


async def test_m25_acceptance_chain(ws):
    """mesh_analyze → mesh_repair → mesh_analyze works over MCP and lands in the version history."""
    write_inbox(ws, with_debris(with_holes(plate_with_bore(), 3)), "scan.stl")
    imported = json.loads(_text(await call("mesh_import", path="scan.stl", project_name="Braket")))
    pid = imported["project_id"]

    before = json.loads(_text(await call("mesh_analyze", project_id=pid)))
    assert before["holes"] == 3 and before["components"] == 3

    await call("mesh_remove_small_components", project_id=pid, min_faces=100, max_deviation_mm=0.3)
    repaired = json.loads(_text(await call("mesh_fill_holes", project_id=pid, max_deviation_mm=0.3)))
    assert repaired["stored"]

    after = json.loads(_text(await call("mesh_analyze", project_id=pid)))
    assert after["watertight"] and after["components"] == 1

    history = json.loads(_text(await call("project_get", project_id=pid)))
    assert [v["tool"] for v in history["versions"]] == ["import", "mesh_remove_small_components", "mesh_fill_holes"]


async def test_errors_are_tool_errors(ws):
    # In-process call_tool raises ToolError; the protocol layer turns it into is_error (see e2e test).
    with pytest.raises(ToolError, match="PathNotAllowed"):
        await call("mesh_import", path="/etc/hosts")

    write_inbox(ws, plate_with_bore(), "p.stl")
    pid = json.loads(_text(await call("mesh_import", path="p.stl")))["project_id"]
    with pytest.raises(ToolError, match="Nothing was stored"):
        await call("mesh_decimate", project_id=pid, target_faces=12, max_deviation_mm=0.01)


async def test_render_returns_images(ws):
    write_inbox(ws, plate_with_bore(), "p.stl")
    pid = json.loads(_text(await call("mesh_import", path="p.stl")))["project_id"]
    result = await call("mesh_render_views", project_id=pid, views=["iso"], size_px=200)
    kinds = [c.type for c in result.content]
    assert kinds == ["text", "image"]


async def test_export_and_report(ws):
    write_inbox(ws, plate_with_bore(), "p.stl")
    pid = json.loads(_text(await call("mesh_import", path="p.stl")))["project_id"]
    out = json.loads(_text(await call("export_asset", project_id=pid, filename="part.3mf")))
    assert out["verified_triangles"] == out["triangles"]
    assert (ws.reports / f"{pid}_report.md").exists() is False
    await call("project_report", project_id=pid)
    assert (ws.reports / f"{pid}_report.md").exists()


async def test_print_tools_over_mcp(ws):
    import trimesh
    bar = trimesh.creation.box((60, 20, 8)).apply_translation((0, 0, 24))
    t = bar.union(trimesh.creation.box((12, 20, 40)), engine="manifold")
    write_inbox(ws, t, "t.stl")
    pid = json.loads(_text(await call("mesh_import", path="t.stl")))["project_id"]
    before = json.loads(_text(await call("print_check", project_id=pid)))
    assert "overhangs" in {i["code"] for i in before["issues"]}
    await call("print_orient_optimize", project_id=pid)
    after = json.loads(_text(await call("print_check", project_id=pid, material="PETG")))
    assert after["printable"] and "overhangs" not in {i["code"] for i in after["issues"]}
    printers = await server.mcp.read_resource("scanlab://printers")
    profiles = json.loads(printers[0].content)
    assert profiles[0]["build_volume_mm"] == [300, 300, 300] and profiles[0]["name"] == "Creality K2 Pro (0.4)"


async def test_make_print_ready_prompt_mentions_printer():
    msgs = await server.mcp.get_prompt("make_print_ready", {"project_id": "x"})
    text = msgs.messages[0].content.text
    assert "Creality K2 Pro" in text and "print_slice_dry_run" in text and "max_deviation_mm=0.3" in text
