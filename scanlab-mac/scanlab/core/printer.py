"""Printer profiles (PRD §2.1, M26 §26.5): YAML files in `scanlab/core/printers/`."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml

PROFILE_DIR = Path(__file__).parent / "printers"


@dataclass(frozen=True)
class Material:
    name: str
    orca_filament: str
    shrinkage_pct: float
    density_g_cm3: float


@dataclass(frozen=True)
class PrinterProfile:
    id: str
    name: str
    build_volume_mm: tuple[float, float, float]
    nozzle_mm: float
    layer_height_mm: float
    min_wall_mm: float
    min_feature_mm: float
    overhang_angle_deg: float
    max_bridge_mm: float
    min_bed_contact_mm2: float
    hole_compensation_mm: float
    elephant_foot_mm: float
    calibrated: bool
    default_material: str
    materials: dict[str, Material]
    orca_machine: str
    orca_process: str
    raw: dict = field(repr=False, compare=False, default_factory=dict)

    def material(self, name: str | None) -> Material:
        key = (name or self.default_material).upper()
        if key not in self.materials:
            raise ValueError(f"material must be one of {sorted(self.materials)}")
        return self.materials[key]

    def summary(self) -> dict:
        return {k: v for k, v in self.raw.items() if k != "orca"} | {"orca": self.raw.get("orca")}


def load_profile(printer_id: str) -> PrinterProfile:
    path = PROFILE_DIR / f"{printer_id}.yaml"
    if not path.is_file() or path.parent != PROFILE_DIR:
        raise ValueError(f"unknown printer {printer_id!r}; available: {list_profiles()}")
    d = yaml.safe_load(path.read_text())
    return PrinterProfile(
        id=d["id"], name=d["name"], build_volume_mm=tuple(d["build_volume_mm"]), nozzle_mm=d["nozzle_mm"],
        layer_height_mm=d["layer_height_mm"], min_wall_mm=d["min_wall_mm"], min_feature_mm=d["min_feature_mm"],
        overhang_angle_deg=d["overhang_angle_deg"], max_bridge_mm=d["max_bridge_mm"],
        min_bed_contact_mm2=d["min_bed_contact_mm2"], hole_compensation_mm=d["hole_compensation_mm"],
        elephant_foot_mm=d["elephant_foot_mm"], calibrated=d["calibrated"], default_material=d["default_material"],
        materials={k.upper(): Material(k.upper(), **v) for k, v in d["materials"].items()},
        orca_machine=d["orca"]["machine"], orca_process=d["orca"]["process"], raw=d,
    )


def list_profiles() -> list[str]:
    return sorted(p.stem for p in PROFILE_DIR.glob("*.yaml"))


DEFAULT_PRINTER = "creality_k2_pro"
