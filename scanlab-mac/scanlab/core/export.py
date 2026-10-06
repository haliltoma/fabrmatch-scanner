"""`export_asset`: write a version to the exchange outbox (M13 formats, mm by default)."""

from __future__ import annotations

from pathlib import Path

import trimesh

from .mesh_io import UNIT_TO_MM

EXPORT_FORMATS = {"stl", "ply", "obj", "glb", "3mf"}


def export(mesh: trimesh.Trimesh, path: Path, unit: str = "mm") -> dict:
    fmt = path.suffix.lower().lstrip(".")
    if fmt not in EXPORT_FORMATS:
        raise ValueError(f"format must be one of {sorted(EXPORT_FORMATS)}")
    if unit not in UNIT_TO_MM:
        raise ValueError(f"unit must be one of {sorted(UNIT_TO_MM)}")
    m = mesh.copy()
    if unit != "mm":
        m.apply_scale(1.0 / UNIT_TO_MM[unit])
    tmp = path.with_name(f".{path.name}.tmp")
    data = m.export(file_type=fmt)
    tmp.write_bytes(data.encode() if isinstance(data, str) else data)  # OBJ comes back as text
    tmp.replace(path)
    reread = trimesh.load(path, force="mesh", process=False)
    return {"path": str(path), "format": fmt, "unit": unit, "bytes": path.stat().st_size,
            "triangles": int(len(m.faces)), "verified_triangles": int(len(reread.faces))}
