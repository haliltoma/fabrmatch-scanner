"""Geometry engine façade (PRD §4.7 "core"): MCP-independent, callable from tests, panel or MCP.

Every mutating operation:
1. loads the requested (or head) version, 2. runs one deterministic operation,
3. measures the result against its parent and the original raw scan,
4. refuses to store it if it exceeds `max_deviation_mm` (M26 deviation budget),
5. stores it as a new version unless `dry_run` — the input is never modified.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass

import trimesh

from . import analyze as _analyze
from . import deviation, mesh_io, render, repair
from .export import export as _export
from .versions import Version, VersionStore
from .workspace import Workspace

Operation = Callable[[trimesh.Trimesh], tuple[trimesh.Trimesh, dict]]


class DeviationBudgetExceeded(RuntimeError):
    def __init__(self, measured: float, budget: float):
        super().__init__(f"p95 deviation {measured:.4f} mm from the raw scan exceeds budget {budget} mm")
        self.measured, self.budget = measured, budget


@dataclass
class OperationResult:
    version: Version | None
    report: dict
    metrics: dict
    deviation_from_parent: dict
    deviation_from_raw: dict
    stored: bool

    def to_dict(self) -> dict:
        return {"stored": self.stored, "version_id": self.version.id if self.version else None,
                "report": self.report, "metrics": self.metrics,
                "deviation_from_parent": self.deviation_from_parent,
                "deviation_from_raw": self.deviation_from_raw}


class Engine:
    def __init__(self, workspace: Workspace):
        self.ws = workspace
        self.store = VersionStore(workspace)

    # Import
    def import_mesh(self, path: str, project_name: str | None = None, unit: str = "mm") -> tuple[Version, dict]:
        src = self.ws.resolve_input(path)
        mesh = mesh_io.load_mesh(src, unit=unit)
        project = self.store.create_project(project_name or src.stem)
        metrics = _analyze.analyze(mesh)
        v = self.store.add_version(project.id, mesh, "import", {"source": src.name, "unit": unit}, metrics, None)
        return v, metrics

    # Read-only
    def analyze(self, project_id: str, version_id: str | None = None) -> dict:
        v = self.store.resolve(project_id, version_id)
        return {"version_id": v.id, **_analyze.analyze(self.store.load(v))}

    def render(self, project_id: str, version_id: str | None = None, views: list[str] | None = None,
               heatmap_against: str | None = None, size_px: int = 512) -> list[tuple[str, bytes]]:
        v = self.store.resolve(project_id, version_id)
        mesh = self.store.load(v)
        heat = None
        if heatmap_against:
            ref = self.store.load(self.store.resolve(project_id, heatmap_against))
            _, heat, _ = trimesh.proximity.closest_point(ref, mesh.triangles_center)
        return render.render_views(mesh, views, size_px=size_px, heatmap=heat)

    def compare(self, project_id: str, version_a: str, version_b: str, samples: int = 20_000) -> dict:
        a = self.store.load(self.store.resolve(project_id, version_a))
        b = self.store.load(self.store.resolve(project_id, version_b))
        return deviation.compare(a, b, samples=samples)

    def raw_version(self, project_id: str) -> Version:
        return self.store.versions(project_id)[0]

    # Mutating
    def apply(self, project_id: str, tool: str, params: dict, op: Operation, version_id: str | None = None,
              dry_run: bool = False, max_deviation_mm: float | None = None) -> OperationResult:
        parent = self.store.resolve(project_id, version_id)
        before = self.store.load(parent)
        after, report = op(before)
        if len(after.faces) == 0:
            raise ValueError(f"{tool} produced an empty mesh")
        raw = self.store.load(self.raw_version(project_id))
        dev_parent = deviation.compare(before, after, samples=5_000)
        dev_raw = deviation.compare(raw, after, samples=5_000)
        if max_deviation_mm is not None and dev_raw["p95_mm"] > max_deviation_mm:
            self.store.log(project_id, "rejected", {"tool": tool, "params": params, "p95_mm": dev_raw["p95_mm"]})
            raise DeviationBudgetExceeded(dev_raw["p95_mm"], max_deviation_mm)
        metrics = _analyze.analyze(after)
        stored = None
        if not dry_run:
            stored = self.store.add_version(project_id, after, tool, params,
                                            {**metrics, "deviation_from_raw": dev_raw}, parent.id)
        return OperationResult(stored, report, metrics, dev_parent, dev_raw, stored is not None)

    def remove_small_components(self, project_id: str, min_faces: int = 50, min_extent_mm: float = 0.0,
                                keep_largest_only: bool = False, **kw) -> OperationResult:
        params = {"min_faces": min_faces, "min_extent_mm": min_extent_mm, "keep_largest_only": keep_largest_only}
        return self.apply(project_id, "mesh_remove_small_components", params,
                          lambda m: repair.remove_small_components(m, **params), **kw)

    def fill_holes(self, project_id: str, max_perimeter_mm: float = 50.0, **kw) -> OperationResult:
        return self.apply(project_id, "mesh_fill_holes", {"max_perimeter_mm": max_perimeter_mm},
                          lambda m: repair.fill_holes(m, max_perimeter_mm), **kw)

    def repair(self, project_id: str, join_components: bool = False, **kw) -> OperationResult:
        return self.apply(project_id, "mesh_repair", {"join_components": join_components},
                          lambda m: repair.repair_full(m, join_components), **kw)

    def fix_normals(self, project_id: str, **kw) -> OperationResult:
        return self.apply(project_id, "mesh_fix_normals", {}, repair.fix_normals, **kw)

    def decimate(self, project_id: str, target_faces: int, **kw) -> OperationResult:
        return self.apply(project_id, "mesh_decimate", {"target_faces": target_faces},
                          lambda m: repair.decimate(m, target_faces), **kw)

    def export(self, project_id: str, filename: str, version_id: str | None = None, unit: str = "mm") -> dict:
        v = self.store.resolve(project_id, version_id)
        result = _export(self.store.load(v), self.ws.resolve_output(filename), unit=unit)
        self.store.log(project_id, "export", {"version_id": v.id, **result})
        return {"version_id": v.id, **result}

    def report_markdown(self, project_id: str) -> str:
        """Version history as `report.md` (M26 §26.6, minimal form)."""
        p = self.store.project(project_id)
        lines = [f"# {p.name} ({p.id})", "", f"head: `{p.head}`", "",
                 "| sürüm | üst | araç | parametreler | üçgen | watertight | delik | ham sapma p95 (mm) |",
                 "|---|---|---|---|---|---|---|---|"]
        for v in self.store.versions(project_id):
            m = v.metrics
            dev = (m.get("deviation_from_raw") or {}).get("p95_mm", "—")
            lines.append(f"| `{v.id}` | `{v.parent_id or '—'}` | {v.tool} | `{json.dumps(v.params)}` | "
                         f"{m.get('triangles')} | {m.get('watertight')} | {m.get('holes')} | {dev} |")
        return "\n".join(lines) + "\n"
