"""Fixed (non-agent) pipeline over the M26 benchmark parts → benchmarks/results.md.

This is the floor the agent loop must beat: same tools, no judgement.
Run: uv run python benchmarks/run_baseline.py
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from parts import PARTS, make_scan  # noqa: E402

from scanlab.core import deviation  # noqa: E402
from scanlab.core.engine import DeviationBudgetExceeded, Engine  # noqa: E402
from scanlab.core.orca import SlicerError  # noqa: E402
from scanlab.core.workspace import Workspace  # noqa: E402

BUDGET_MM = 0.3


def run_part(engine: Engine, name: str, seed: int) -> dict:
    truth = PARTS[name]()
    scan = make_scan(truth, seed)
    scan.export(engine.ws.inbox / f"{name}.ply")
    raw, raw_metrics = engine.import_mesh(f"{name}.ply", name)
    pid = raw.project_id
    steps = []

    def step(label, fn):
        try:
            r = fn()
            steps.append(label)
            return r
        except DeviationBudgetExceeded:
            steps.append(f"{label}✗budget")
            return None

    step("components", lambda: engine.remove_small_components(pid, min_faces=200, max_deviation_mm=BUDGET_MM))
    step("fill", lambda: engine.fill_holes(pid, max_perimeter_mm=30, max_deviation_mm=BUDGET_MM))
    step("normals", lambda: engine.fix_normals(pid, max_deviation_mm=BUDGET_MM))
    if not engine.analyze(pid)["watertight"]:
        step("meshfix", lambda: engine.repair(pid, max_deviation_mm=BUDGET_MM))
    step("orient", lambda: engine.orient_for_print(pid, max_deviation_mm=BUDGET_MM))
    if "rough_base" in {i["code"] for i in engine.print_check(pid)["issues"]}:
        step("flatten_base", lambda: engine.flatten_base(pid, max_deviation_mm=BUDGET_MM))

    final = engine.store.head(pid)
    m = final.metrics
    shape = engine.load_in_raw_frame(final)
    vs_truth = deviation.compare(truth, shape, samples=10_000)
    check = engine.print_check(pid)
    try:
        sliced = engine.slice_dry_run(pid)
        slice_ok, time_s, grams = True, sliced.get("time"), sliced.get("filament_g")
    except SlicerError as e:
        slice_ok, time_s, grams = False, str(e)[:60], None
    return {
        "part": name, "holes_before": raw_metrics["holes"], "components_before": raw_metrics["components"],
        "steps": " → ".join(steps), "watertight": m["watertight"], "manifold": m["manifold"],
        "components": m["components"], "dev_raw_p95": (m.get("deviation_from_raw") or {}).get("p95_mm", 0.0),
        "dev_truth_p95": vs_truth["p95_mm"], "dev_truth_max": vs_truth["hausdorff_mm"],
        "volume_err_pct": round(abs(shape.volume - truth.volume) / truth.volume * 100, 2) if m["watertight"] else None,
        "printable": check["printable"], "warnings": sorted({i["code"] for i in check["issues"] if i["severity"] == "warning"}),
        "slice_ok": slice_ok, "print_time": time_s, "filament_g": grams, "versions": len(engine.store.versions(pid)),
    }


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        engine = Engine(Workspace.create(Path(tmp)))
        rows = [run_part(engine, name, seed) for seed, name in enumerate(PARTS)]
    cols = ["part", "holes_before", "components_before", "steps", "watertight", "components", "dev_raw_p95",
            "dev_truth_p95", "dev_truth_max", "volume_err_pct", "printable", "warnings", "slice_ok", "print_time",
            "filament_g"]
    lines = ["# M26 benchmark — sabit hat (ajansız taban çizgisi)", "",
             f"Yazıcı: Creality K2 Pro 0.4, PLA · sapma bütçesi {BUDGET_MM} mm · tarama: 0,05 mm gürültü, 4 boşluk, 2 kopuk parça",
             "", "| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        lines.append("| " + " | ".join(str(r[c]) for c in cols) + " |")
    passed = sum(r["watertight"] and r["manifold"] and r["components"] == 1 and r["slice_ok"]
                 and r["dev_raw_p95"] <= BUDGET_MM for r in rows)
    lines += ["", f"**Geçen: {passed}/{len(rows)}** (watertight + manifold + tek gövde + dilimleme + bütçe)", ""]
    out = Path(__file__).parent / "results.md"
    out.write_text("\n".join(lines))
    print("\n".join(lines))
    print(json.dumps(rows, indent=1, default=str)[:0])
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
