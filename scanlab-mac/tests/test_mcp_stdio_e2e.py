"""End-to-end: launch `scanlab-mcp` as a subprocess and talk to it over stdio like Claude does (M25 acceptance)."""

import json
import os
import sys

from mcp import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client

from conftest import plate_with_bore, with_holes, write_inbox


async def test_stdio_client_lists_tools_and_runs_chain(ws):
    write_inbox(ws, with_holes(plate_with_bore(), 2), "scan.stl")
    params = StdioServerParameters(
        command=sys.executable, args=["-m", "scanlab.mcp_server.server"],
        env={**os.environ, "SCANLAB_HOME": str(ws.home), "SCANLAB_EXCHANGE": str(ws.exchange)},
    )
    async with stdio_client(params) as (read, write), ClientSession(read, write) as session:
        await session.initialize()
        tools = {t.name for t in (await session.list_tools()).tools}
        assert "mesh_analyze" in tools and "mesh_repair" in tools

        imported = json.loads((await session.call_tool("mesh_import", {"path": "scan.stl"})).content[0].text)
        pid = imported["project_id"]
        assert imported["metrics"]["holes"] == 2

        repaired = await session.call_tool("mesh_repair", {"project_id": pid, "max_deviation_mm": 0.5})
        assert not repaired.is_error
        after = json.loads((await session.call_tool("mesh_analyze", {"project_id": pid})).content[0].text)
        assert after["watertight"] and after["holes"] == 0

        refused = await session.call_tool("mesh_import", {"path": "/etc/hosts"})
        assert refused.is_error

        prompts = {p.name for p in (await session.list_prompts()).prompts}
        assert {"inspect_scan_quality", "make_print_ready"} <= prompts
