# Cross-language fixtures

`chunk_v1.bin` — one SLMC v1 mesh chunk (`raw/mesh_chunks/*.bin`), written independently from the
format spec in `MeshChunkCodec.swift`. Both `ScanLabKitTests` (Swift encoder must produce these exact bytes)
and `scanlab-mac/tests` (Python reader must decode them) check against it, so the iPhone and Mac sides
cannot drift apart silently.

id `00112233-4455-6677-8899-AABBCCDDEEFF`, version 7, translation (1, 2, 3) m, unit floor quad, classes [2, 2].

`frame_v1.sldf` — one SLDF v1 raw depth frame (`scanlab-mac/scanlab/recon/capture.py` documents the layout):
4×3 pixels, fx 200, fy 201, cx 2, cy 1.5, pose translation (0.1, 0.2, 0.3) m, timestamp 12.5 s.
The Swift `DepthFrameCodec` must reproduce it byte for byte; the Python reader must decode it.
