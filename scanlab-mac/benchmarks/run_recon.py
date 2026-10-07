"""Reconstruction benchmark: every algorithm vs CAD truth, and does the blind selector pick well?

5 parts × {LiDAR, TrueDepth} synthetic captures (table, noise, flying pixels, tracking error).
For each scenario: truth F-score@τ of every candidate, blind F, the selector's pick, the oracle
(best by truth) and the regret = F_truth(oracle) − F_truth(pick).
Run: uv run python benchmarks/run_recon.py  [--sensors truedepth] [--parts holed_bracket]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from parts import PARTS  # noqa: E402

from scanlab.recon.pipeline import pick_best, reconstruct_all, truth_score  # noqa: E402
from scanlab.recon.simulate import SENSORS, placed_truth, simulate_capture  # noqa: E402

TAU_TRUTH = {"lidar": 2.0, "truedepth": 0.5}
NEAR = 0.02  # a pick within this F of the oracle counts as a good pick


def run(parts: list[str], sensors: list[str]) -> list[dict]:
    rows = []
    for si, sensor in enumerate(sensors):
        for pi, part in enumerate(parts):
            t = time.time()
            truth = placed_truth(PARTS[part]())
            cap, _ = simulate_capture(PARTS[part](), SENSORS[sensor], seed=10 * si + pi)
            try:
                scene, cands = reconstruct_all(cap)
            except ValueError as e:  # e.g. part thinner than the sensor's table band
                rows.append({"sensor": sensor, "part": part, "seconds": round(time.time() - t, 1), "pick": "—",
                             "pick_truth_f": None, "pick_chamfer_mm": None, "oracle": "—", "oracle_truth_f": None,
                             "regret": None, "failed": str(e), "candidates": {}})
                print(f"{sensor:9s} {part:16s} FAILED: {e}", flush=True)
                continue
            for c in cands:
                if c.ok:
                    c.truth = truth_score(c.mesh, truth, TAU_TRUTH[sensor])
            ok = [c for c in cands if c.ok]
            pick = pick_best(cands)
            oracle = max(ok, key=lambda c: c.truth["f"])
            rows.append({
                "sensor": sensor, "part": part, "seconds": round(time.time() - t, 1),
                "pick": pick.name, "pick_truth_f": pick.truth["f"], "pick_chamfer_mm": pick.truth["chamfer_mm"],
                "oracle": oracle.name, "oracle_truth_f": oracle.truth["f"],
                "regret": round(oracle.truth["f"] - pick.truth["f"], 4),
                "candidates": {c.name: {"blind_f": c.blind.get("f"), "depth_rmse": c.blind.get("depth_rmse_mm"), "truth_f": c.truth.get("f"),
                                        "chamfer_mm": c.truth.get("chamfer_mm"), "error": c.error,
                                        "seconds": c.seconds} for c in cands},
            })
            r = rows[-1]
            print(f"{sensor:9s} {part:16s} pick {r['pick']:13s} F={r['pick_truth_f']} | oracle {r['oracle']:13s} "
                  f"F={r['oracle_truth_f']} | regret {r['regret']} | {r['seconds']}s", flush=True)
    return rows


def write_report(rows: list[dict], path: Path) -> None:
    algos = sorted({a for r in rows for a in r["candidates"]})
    lines = ["# Yeniden yapılandırma benchmark'ı", "",
             "Sentetik taramalar (masa, mesafeye bağlı gürültü, uçan pikseller, sıyırma kaybı, poz hatası). "
             f"Gerçek F-skoru eşiği: LiDAR {TAU_TRUTH['lidar']} mm, TrueDepth {TAU_TRUTH['truedepth']} mm.", "",
             "## Seçici", "", "| sensör | parça | seçilen | F (CAD) | chamfer mm | en iyi (CAD) | F | pişmanlık |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if r["regret"] is None:
            lines.append(f"| {r['sensor']} | {r['part']} | — | — | — | — | — | {r['failed'][:70]} |")
            continue
        lines.append(f"| {r['sensor']} | {r['part']} | {r['pick']} | {r['pick_truth_f']} | {r['pick_chamfer_mm']} | "
                     f"{r['oracle']} | {r['oracle_truth_f']} | {r['regret']} |")
    scored = [r for r in rows if r["regret"] is not None]
    good = sum(r["regret"] <= NEAR for r in scored)
    failed = [r for r in rows if r["regret"] is None]
    lines += ["", f"**İyi seçim (pişmanlık ≤ {NEAR}): {good}/{len(scored)}**" +
              (f" · yeniden yapılandırılamayan: {len(failed)} (" + ", ".join(f"{r['sensor']}/{r['part']}" for r in failed) + ")"
               if failed else ""), "",
              "## Algoritmaların CAD'e F-skoru (kör: ayrılmış karelerde derinlik RMSE, mm)", "", "| sensör | parça | " + " | ".join(algos) + " |",
              "|---|---|" + "---|" * len(algos)]
    for r in rows:
        cells = []
        for a in algos:
            c = r["candidates"].get(a, {})
            cells.append("hata" if c.get("error") else f"{c.get('truth_f')} ({c.get('depth_rmse')})")
        lines.append(f"| {r['sensor']} | {r['part']} | " + " | ".join(cells) + " |")
    path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--sensors", nargs="*", default=["truedepth", "lidar"])
    ap.add_argument("--parts", nargs="*", default=list(PARTS))
    args = ap.parse_args()
    rows = run(args.parts, args.sensors)
    out = Path(__file__).parent
    (out / "results_recon.json").write_text(json.dumps(rows, indent=1))
    write_report(rows, out / "results_recon.md")
    scored = [r for r in rows if r["regret"] is not None]
    print(f"good picks: {sum(r['regret'] <= NEAR for r in scored)}/{len(scored)}")
