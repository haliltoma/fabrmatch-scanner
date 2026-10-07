"""Raw capture format: what the iPhone records so the Mac can try many reconstruction algorithms.

Folder layout:
    capture.json            {"format": "scanlab-capture", "version": 1, "sensor": "lidar"|"truedepth",
                             "frames": ["depth/000001.sldf", ...]}
    depth/NNNNNN.sldf       one frame each

SLDF v1 (little-endian):
    "SLDF" | u16 version=1 | u16 reserved | u32 width | u32 height | f32 fx, fy, cx, cy |
    f32[16] camera→world pose, column-major, meters | f64 timestamp |
    f32 depth[height·width] row-major, meters, 0 = invalid | u8 confidence[height·width] (0 low, 1 mid, 2 high)

Camera convention is ARKit's: +X right, +Y up, the camera looks down −Z; pixel v grows downward.
Intrinsics are for the depth map's own resolution.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

MAGIC = b"SLDF"
_HEADER = struct.Struct("<4sHHII4f16fd")
# OpenCV camera (+Y down, +Z forward) from ARKit camera (+Y up, −Z forward).
ARKIT_TO_CV = np.diag([1.0, -1.0, -1.0, 1.0])


class CaptureFormatError(ValueError):
    pass


@dataclass
class DepthFrame:
    depth: np.ndarray        # (h, w) float32 meters, 0 = invalid
    confidence: np.ndarray   # (h, w) uint8
    fx: float
    fy: float
    cx: float
    cy: float
    pose: np.ndarray         # (4, 4) camera→world, ARKit convention
    timestamp: float = 0.0

    @property
    def size(self) -> tuple[int, int]:
        return self.depth.shape[1], self.depth.shape[0]

    @property
    def camera_center(self) -> np.ndarray:
        return self.pose[:3, 3]

    def extrinsic_cv(self) -> np.ndarray:
        """World→camera in OpenCV convention (what Open3D's TSDF integration expects)."""
        return ARKIT_TO_CV @ np.linalg.inv(self.pose)

    def points(self, min_confidence: int = 1, max_depth: float | None = None) -> tuple[np.ndarray, np.ndarray]:
        """World-space points (n, 3) in meters and their pixel mask (h, w)."""
        mask = (self.depth > 0) & (self.confidence >= min_confidence)
        if max_depth is not None:
            mask &= self.depth <= max_depth
        v, u = np.nonzero(mask)
        d = self.depth[v, u].astype(np.float64)
        cam = np.stack([(u - self.cx) * d / self.fx, -(v - self.cy) * d / self.fy, -d, np.ones_like(d)], axis=1)
        return (cam @ self.pose.T)[:, :3], mask

    def encode(self) -> bytes:
        h, w = self.depth.shape
        if self.confidence.shape != (h, w):
            raise CaptureFormatError("confidence shape differs from depth")
        header = _HEADER.pack(MAGIC, 1, 0, w, h, self.fx, self.fy, self.cx, self.cy,
                              *self.pose.astype(np.float32).T.ravel(), self.timestamp)
        return header + self.depth.astype("<f4").tobytes() + self.confidence.astype(np.uint8).tobytes()

    @classmethod
    def decode(cls, data: bytes) -> "DepthFrame":
        if len(data) < _HEADER.size:
            raise CaptureFormatError("truncated header")
        magic, ver, _r, w, h, fx, fy, cx, cy, *rest = _HEADER.unpack_from(data)
        if magic != MAGIC:
            raise CaptureFormatError("bad magic")
        if ver != 1:
            raise CaptureFormatError(f"unsupported version {ver}")
        pose = np.array(rest[:16], dtype=np.float64).reshape(4, 4).T
        timestamp = rest[16]
        n = w * h
        if len(data) != _HEADER.size + n * 5:
            raise CaptureFormatError("payload size mismatch")
        depth = np.frombuffer(data, "<f4", n, _HEADER.size).reshape(h, w).copy()
        conf = np.frombuffer(data, np.uint8, n, _HEADER.size + n * 4).reshape(h, w).copy()
        return cls(depth, conf, fx, fy, cx, cy, pose, timestamp)


@dataclass
class Capture:
    sensor: str
    frames: list[DepthFrame]

    def save(self, directory: Path) -> None:
        (directory / "depth").mkdir(parents=True, exist_ok=True)
        names = []
        for i, f in enumerate(self.frames, 1):
            name = f"depth/{i:06d}.sldf"
            (directory / name).write_bytes(f.encode())
            names.append(name)
        (directory / "capture.json").write_text(json.dumps(
            {"format": "scanlab-capture", "version": 1, "sensor": self.sensor, "frames": names}, indent=1))

    @classmethod
    def load(cls, directory: Path) -> "Capture":
        meta_path = directory / "capture.json"
        if not meta_path.exists():
            raise CaptureFormatError(f"no capture.json in {directory}")
        meta = json.loads(meta_path.read_text())
        if meta.get("format") != "scanlab-capture" or meta.get("version") != 1:
            raise CaptureFormatError("not a scanlab-capture v1 folder")
        frames = []
        for name in meta["frames"]:
            p = (directory / name).resolve()
            if not p.is_relative_to(directory.resolve()):
                raise CaptureFormatError(f"frame path escapes capture folder: {name}")
            frames.append(DepthFrame.decode(p.read_bytes()))
        if not frames:
            raise CaptureFormatError("capture has no frames")
        return cls(meta.get("sensor", "lidar"), frames)
