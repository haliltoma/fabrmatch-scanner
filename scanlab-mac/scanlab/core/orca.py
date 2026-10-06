"""Headless OrcaSlicer slicing for `print_slice_dry_run` (PRD M26 stage 6).

Orca's system presets use `inherits` chains; the CLI wants self-contained files, so presets are
flattened here. Dimensional compensation from the printer profile is applied as slicer settings.
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import tempfile
from functools import cache
from pathlib import Path

import trimesh

from .printer import Material, PrinterProfile

ORCA_APP = Path(os.environ.get("SCANLAB_ORCA_APP", "/Applications/OrcaSlicer.app"))
ORCA_BIN = ORCA_APP / "Contents/MacOS/OrcaSlicer"
PROFILE_ROOT = ORCA_APP / "Contents/Resources/profiles"


class SlicerError(RuntimeError):
    pass


@cache
def _preset_index() -> dict[tuple[str, str], dict]:
    index: dict[tuple[str, str], dict] = {}
    for path in glob.glob(str(PROFILE_ROOT / "**/*.json"), recursive=True):
        kind = Path(path).parent.name
        if kind not in {"machine", "process", "filament"}:
            continue
        try:
            data = json.loads(Path(path).read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and "name" in data:
            index.setdefault((kind, data["name"]), data)
    return index


def flatten_preset(kind: str, name: str) -> dict:
    index = _preset_index()
    if (kind, name) not in index:
        raise SlicerError(f"OrcaSlicer {kind} preset not found: {name!r}")
    chain = [index[(kind, name)]]
    while parent := chain[-1].get("inherits"):
        if (kind, parent) not in index:
            raise SlicerError(f"broken inherits chain at {parent!r}")
        chain.append(index[(kind, parent)])
    merged: dict = {}
    for d in reversed(chain):
        merged.update(d)
    merged.pop("inherits", None)
    merged["name"] = name
    return merged


_STATS = {
    "time": re.compile(r"^; estimated printing time \(normal mode\) = (.+)$", re.M),
    "first_layer_time": re.compile(r"^; estimated first layer printing time \(normal mode\) = (.+)$", re.M),
    "filament_mm": re.compile(r"^; filament used \[mm\] = ([\d.]+)", re.M),
    "filament_cm3": re.compile(r"^; filament used \[cm3\] = ([\d.]+)", re.M),
    "filament_g": re.compile(r"^; total filament used \[g\] = ([\d.]+)", re.M),
    "layers": re.compile(r"^; total layer number: (\d+)", re.M),
    "max_z_mm": re.compile(r"^; max_z_height: ([\d.]+)", re.M),
}


def _duration_seconds(text: str) -> int:
    units = {"d": 86400, "h": 3600, "m": 60, "s": 1}
    return sum(int(n) * units[u] for n, u in re.findall(r"(\d+)([dhms])", text))


def parse_gcode_stats(gcode: str) -> dict:
    out: dict = {}
    for key, rx in _STATS.items():
        m = rx.search(gcode)
        if m:
            out[key] = m.group(1).strip()
    if "time" in out:
        out["time_s"] = _duration_seconds(out["time"])
    for k in ("filament_mm", "filament_cm3", "filament_g", "max_z_mm"):
        if k in out:
            out[k] = float(out[k])
    if "layers" in out:
        out["layers"] = int(out["layers"])
    return out


def slice_mesh(mesh: trimesh.Trimesh, profile: PrinterProfile, material: Material, workdir: Path,
               infill_pct: int | None = None, wall_loops: int | None = None, supports: bool = False,
               timeout_s: int = 300) -> dict:
    """Slices `mesh` (mm, already oriented: z up, resting on z=0) and returns G-code statistics."""
    if not ORCA_BIN.exists():
        raise SlicerError(f"OrcaSlicer not found at {ORCA_APP}")
    workdir.mkdir(parents=True, exist_ok=True)
    process = flatten_preset("process", profile.orca_process)
    process["xy_hole_compensation"] = str(profile.hole_compensation_mm)
    process["elefant_foot_compensation"] = str(profile.elephant_foot_mm)
    process["enable_support"] = "1" if supports else "0"
    if infill_pct is not None:
        process["sparse_infill_density"] = f"{int(infill_pct)}%"
    if wall_loops is not None:
        process["wall_loops"] = str(int(wall_loops))
    files = {"machine.json": flatten_preset("machine", profile.orca_machine), "process.json": process,
             "filament.json": flatten_preset("filament", material.orca_filament)}
    with tempfile.TemporaryDirectory(dir=workdir) as tmp:
        t = Path(tmp)
        for name, data in files.items():
            (t / name).write_text(json.dumps(data))
        mesh.export(t / "part.stl")
        cmd = [str(ORCA_BIN), "--slice", "0", "--load-settings", f"{t/'machine.json'};{t/'process.json'}",
               "--load-filaments", str(t / "filament.json"), "--arrange", "1", "--orient", "0",
               "--outputdir", str(t / "out"), str(t / "part.stl")]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        except subprocess.TimeoutExpired as e:
            raise SlicerError(f"OrcaSlicer timed out after {timeout_s}s") from e
        gcodes = sorted((t / "out").glob("*.gcode")) if (t / "out").exists() else []
        if proc.returncode != 0 or not gcodes:
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-8:]
            raise SlicerError(f"slicing failed (exit {proc.returncode}): {' | '.join(tail)}")
        gcode = gcodes[0].read_text(errors="replace")
        kept = workdir / "last_slice.gcode"
        kept.write_text(gcode)
    stats = parse_gcode_stats(gcode)
    return {"ok": True, "printer": profile.name, "material": material.name, "gcode": str(kept),
            "settings": {"process": profile.orca_process, "infill": process["sparse_infill_density"],
                         "wall_loops": process.get("wall_loops"), "supports": supports,
                         "xy_hole_compensation_mm": profile.hole_compensation_mm,
                         "elephant_foot_mm": profile.elephant_foot_mm, "calibrated": profile.calibrated},
            **stats}
