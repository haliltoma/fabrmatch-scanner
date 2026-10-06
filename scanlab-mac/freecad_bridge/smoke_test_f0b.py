"""F0b smoke test (PRD M28 §28.9): verifies FreeCAD ↔ freecad-mcp bridge end to end.

Uses the same client class (`freecad_mcp.freecad_client.FreeCADConnection`) the MCP
server uses, so a pass here means the MCP tools' transport path works.

Run (FreeCAD open with the MCP addon RPC server started):
    uvx --from freecad-mcp==0.1.25 python scanlab-mac/freecad_bridge/smoke_test_f0b.py
"""

from __future__ import annotations

import base64
import json
import math
import struct
import sys
from pathlib import Path

from freecad_mcp.freecad_client import FreeCADConnection

ROOT = Path(__file__).resolve().parents[1]
EXCHANGE = ROOT / "cad_exchange"
DOC = "F0b_Smoke"
TOL = 1e-3


def run_code(fc: FreeCADConnection, code: str) -> dict:
    """Runs a fixed snippet in FreeCAD and returns the JSON it prints on its last line."""
    res = fc.execute_code(code)
    if not res.get("success"):
        raise RuntimeError(res)
    output = res["message"].split("Output: ", 1)[1].strip()
    return json.loads(output.splitlines()[-1])


def write_plate_stl(path: Path, sx: float, sy: float, sz: float) -> None:
    """Closed box as binary STL in mm, same layout ScanLabExport writes (80B header, u32, 50B/tri)."""
    v = [(x, y, z) for z in (0, sz) for y in (0, sy) for x in (0, sx)]
    faces = [(0, 2, 3), (0, 3, 1), (4, 5, 7), (4, 7, 6), (0, 1, 5), (0, 5, 4),
             (2, 6, 7), (2, 7, 3), (1, 3, 7), (1, 7, 5), (0, 4, 6), (0, 6, 2)]
    data = bytearray(b"ScanLab F0b".ljust(80, b" "))
    data += struct.pack("<I", len(faces))
    for a, b, c in faces:
        data += struct.pack("<3f", 0, 0, 0)
        for i in (a, b, c):
            data += struct.pack("<3f", *v[i])
        data += struct.pack("<H", 0)
    path.write_bytes(data)


def main() -> int:
    report: dict = {"steps": {}}
    fc = FreeCADConnection(host="127.0.0.1", port=9875)

    # 1 — record versions
    status = fc.get_rpc_status()
    versions = run_code(fc, "import FreeCAD, json; print(json.dumps({'freecad': '.'.join(FreeCAD.Version()[:3]), 'build': FreeCAD.Version()[3]}))")
    report["versions"] = {**versions, "addon": status.get("addon_version") or status.get("version"), "rpc_status": status}
    report["steps"]["1_record"] = True

    # 2 — connection
    report["steps"]["2_connection"] = bool(fc.ping())

    # 3 — basic modelling: 20×20×10 mm box with a Ø5 mm through hole, via the structured tools
    if DOC in fc.list_documents():
        run_code(fc, f"import FreeCAD, json; FreeCAD.closeDocument('{DOC}'); print(json.dumps({{}}))")
    fc.create_document(DOC)
    fc.create_object(DOC, {"Name": "Box", "Type": "Part::Box", "Properties": {"Length": 20, "Width": 20, "Height": 10}})
    fc.create_object(DOC, {"Name": "Drill", "Type": "Part::Cylinder", "Properties": {
        "Radius": 2.5, "Height": 10, "Placement": {"Base": {"x": 10, "y": 10, "z": 0}}}})
    part = run_code(fc, f"""
import FreeCAD, json
doc = FreeCAD.getDocument('{DOC}')
cut = doc.addObject('Part::Cut', 'Plate')
cut.Base = doc.Box; cut.Tool = doc.Drill
doc.recompute()
s = cut.Shape
holes = [e.Curve.Radius for e in s.Edges if e.Curve.TypeId == 'Part::GeomCircle']
bb = s.BoundBox
print(json.dumps({{'volume': s.Volume, 'valid': s.isValid(), 'solid': s.ShapeType,
                   'bbox': [bb.XLength, bb.YLength, bb.ZLength], 'hole_radii': sorted(set(round(r, 6) for r in holes))}}))
""")
    expected_volume = 20 * 20 * 10 - math.pi * 2.5 ** 2 * 10
    report["part"] = part
    report["steps"]["3_model"] = (
        part["valid"] and abs(part["volume"] - expected_volume) < TOL
        and part["bbox"] == [20.0, 20.0, 10.0] and part["hole_radii"] == [2.5]
    )
    shot = fc.get_active_screenshot("Isometric")
    if shot:
        (EXCHANGE / "reports" / "f0b_model.png").write_bytes(base64.b64decode(shot))
    report["screenshot"] = bool(shot)

    # 4 — import an STL from the exchange folder and read mesh facts
    stl_in = EXCHANGE / "in" / "plate_30x20x5.stl"
    write_plate_stl(stl_in, 30, 20, 5)
    mesh = run_code(fc, f"""
import Mesh, json
m = Mesh.Mesh({str(stl_in)!r})
bb = m.BoundBox
print(json.dumps({{'facets': m.CountFacets, 'points': m.CountPoints, 'solid': m.isSolid(),
                   'bbox': [bb.XLength, bb.YLength, bb.ZLength], 'volume': m.Volume}}))
""")
    report["mesh_import"] = mesh
    report["steps"]["4_import"] = (
        mesh["facets"] == 12 and mesh["points"] == 8 and mesh["solid"]
        and mesh["bbox"] == [30.0, 20.0, 5.0] and abs(mesh["volume"] - 3000) < TOL
    )

    # 5 — export STEP + STL, then read both back
    step_out, stl_out = EXCHANGE / "out" / "f0b_plate.step", EXCHANGE / "out" / "f0b_plate.stl"
    back = run_code(fc, f"""
import FreeCAD, Part, Mesh, MeshPart, json
s = FreeCAD.getDocument('{DOC}').Plate.Shape
s.exportStep({str(step_out)!r})
m = MeshPart.meshFromShape(Shape=s, LinearDeflection=0.01, AngularDeflection=0.0872665)
m.write({str(stl_out)!r})
r = Part.Shape(); r.read({str(step_out)!r})
rm = Mesh.Mesh({str(stl_out)!r})
print(json.dumps({{'step_volume': r.Volume, 'step_valid': r.isValid(), 'stl_solid': rm.isSolid(),
                   'stl_volume': rm.Volume, 'stl_facets': rm.CountFacets}}))
""")
    report["export"] = back
    report["steps"]["5_export"] = (
        back["step_valid"] and abs(back["step_volume"] - expected_volume) < TOL
        and back["stl_solid"] and abs(back["stl_volume"] - expected_volume) / expected_volume < 0.01
        and step_out.stat().st_size > 0 and stl_out.stat().st_size > 84
    )

    report["passed"] = all(report["steps"].values())
    (EXCHANGE / "reports" / "f0b_smoke.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
