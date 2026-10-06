# ScanLab (fabrmatch-scanner)

Native iOS LiDAR 3D scanner. Spec: `docs/3D-Tarayici-PRD.md`. Plan & status: `tasks/plan.md`, `tasks/todo.md`. Decisions: `docs/adr/`.

## Layout
- `Packages/ScanLabKit/` — platform-independent core (Foundation + simd only, no ARKit/UIKit):
  `ScanLabCore` (models, ProjectStore, MeshStore, MeshMerger, thermal policy), `ScanLabExport` (STL/PLY/OBJ + readers), `ScanLabSensor` (M22 rules).
- `App/ScanLab/` — SwiftUI app, organized by feature (`Features/<Feature>/`). ARKit lives only here.
- `scanlab-mac/` — Python 3.12 (uv) geometry engine `scanlab/core` (MCP-independent) + thin `scanlab/mcp_server` (PRD M25). Engine unit: mm.
- `fixtures/` — cross-language golden files shared by Swift and Python tests.
- `project.yml` — XcodeGen spec; never hand-edit `.xcodeproj` (it is git-ignored).

## Commands
- Tests (works with Command Line Tools only): `scripts/test.sh`
- Mac engine tests: `cd scanlab-mac && uv run pytest`
- Print-prep baseline benchmark: `cd scanlab-mac && uv run python benchmarks/run_baseline.py` (needs OrcaSlicer)
- FreeCAD smoke test: `uvx --from freecad-mcp==0.1.25 python scanlab-mac/freecad_bridge/smoke_test_f0b.py`
- App: `brew install xcodegen && xcodegen && open ScanLab.xcodeproj` (needs full Xcode)

## Conventions
- Swift 6 language mode. Package: no default isolation, shared mutable state in `actor`s.
  App: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; values crossing to ARKit queues or `@concurrent` jobs are `nonisolated`.
- Logic goes in the package with Swift Testing tests; the app layer stays thin.
- One type per file. No third-party dependencies without an ADR.
- Model dates are rounded to whole seconds (`Date.persistable`) so they round-trip through `project.json`.
- User-facing strings are Turkish; code, comments, identifiers English.
- PRD requirement IDs (FR-x.y, Mx) are cited in doc comments where a type implements them.
