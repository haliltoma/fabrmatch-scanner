"""Mesh import: common formats and the iPhone chunk files (`raw/mesh_chunks/*.bin`).

Engine unit is the millimeter (engineering tolerances, CAD, slicers). iPhone data is meters.
"""

from __future__ import annotations

import struct
import uuid
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh

UNIT_TO_MM = {"mm": 1.0, "cm": 10.0, "m": 1000.0, "in": 25.4, "ft": 304.8}
SUPPORTED_IMPORT = {".stl", ".ply", ".obj", ".glb", ".gltf", ".off", ".3mf"}


class ChunkFormatError(ValueError):
    pass


@dataclass(frozen=True)
class MeshChunk:
    id: uuid.UUID
    version: int
    transform: np.ndarray  # 4×4, column-major on disk, stored here as a regular matrix
    vertices: np.ndarray   # (n, 3) float32, anchor-local meters
    indices: np.ndarray    # (m, 3) uint32
    classifications: np.ndarray  # (m,) uint8 or empty

    def world_vertices(self) -> np.ndarray:
        h = np.c_[self.vertices.astype(np.float64), np.ones(len(self.vertices))]
        return (h @ self.transform.T)[:, :3]


_HEADER = struct.Struct("<4sHH16sQ16fIII")


def read_chunk(data: bytes) -> MeshChunk:
    """Decodes SLMC v1, the layout written by `MeshChunkCodec` in ScanLabKit."""
    if len(data) < _HEADER.size:
        raise ChunkFormatError("truncated header")
    magic, fmt, _reserved, raw_id, version, *rest = _HEADER.unpack_from(data)
    if magic != b"SLMC":
        raise ChunkFormatError("bad magic")
    if fmt != 1:
        raise ChunkFormatError(f"unsupported format version {fmt}")
    floats, (nv, ni, nc) = rest[:16], rest[16:]
    if ni % 3:
        raise ChunkFormatError("index count not a multiple of 3")
    if len(data) - _HEADER.size != nv * 12 + ni * 4 + nc:
        raise ChunkFormatError("payload size mismatch")
    off = _HEADER.size
    vertices = np.frombuffer(data, "<f4", nv * 3, off).reshape(nv, 3)
    off += nv * 12
    indices = np.frombuffer(data, "<u4", ni, off)
    off += ni * 4
    if ni and indices.max() >= nv:
        raise ChunkFormatError("index out of range")
    classes = np.frombuffer(data, np.uint8, nc, off)
    transform = np.array(floats, dtype=np.float64).reshape(4, 4).T  # columns on disk → matrix
    # Swift's uuid tuple is the RFC 4122 byte order, same as Python's `bytes`.
    return MeshChunk(uuid.UUID(bytes=raw_id), version, transform, vertices, indices.reshape(-1, 3), classes)


def import_chunks(directory: Path, weld_mm: float = 5.0) -> trimesh.Trimesh:
    """Merges all chunk files into one world-space mesh in millimeters (mirrors `MeshMerger`)."""
    files = sorted(directory.glob("*.bin"))
    if not files:
        raise FileNotFoundError(f"no chunk files in {directory}")
    vertices, faces, offset = [], [], 0
    for f in files:
        c = read_chunk(f.read_bytes())
        vertices.append(c.world_vertices() * 1000.0)
        faces.append(c.indices.astype(np.int64) + offset)
        offset += len(c.vertices)
    mesh = trimesh.Trimesh(np.vstack(vertices), np.vstack(faces), process=False)
    return weld(mesh, weld_mm)


def weld(mesh: trimesh.Trimesh, tolerance_mm: float) -> trimesh.Trimesh:
    """Merges vertices closer than `tolerance_mm` and drops faces that collapse."""
    m = mesh.copy()
    m.merge_vertices(merge_tex=True, merge_norm=True, digits_vertex=None)
    if tolerance_mm > 0:
        from scipy.spatial import cKDTree

        pairs = cKDTree(m.vertices).query_pairs(tolerance_mm, output_type="ndarray")
        if len(pairs):
            parent = np.arange(len(m.vertices))

            def find(i: int) -> int:
                while parent[i] != i:
                    parent[i] = parent[parent[i]]
                    i = parent[i]
                return i

            for a, b in pairs:
                ra, rb = find(a), find(b)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
            roots = np.array([find(i) for i in range(len(parent))])
            m = trimesh.Trimesh(m.vertices, roots[m.faces], process=False)
    m.update_faces(m.nondegenerate_faces())
    m.remove_unreferenced_vertices()
    return m


def load_mesh(path: Path, unit: str = "mm") -> trimesh.Trimesh:
    if path.is_dir():
        return import_chunks(path)
    if path.suffix.lower() not in SUPPORTED_IMPORT:
        raise ValueError(f"unsupported format {path.suffix}; supported: {sorted(SUPPORTED_IMPORT)}")
    if unit not in UNIT_TO_MM:
        raise ValueError(f"unit must be one of {sorted(UNIT_TO_MM)}")
    loaded = trimesh.load(path, force="mesh", process=True)
    if not isinstance(loaded, trimesh.Trimesh) or len(loaded.faces) == 0:
        raise ValueError(f"{path.name} contains no triangle mesh")
    if UNIT_TO_MM[unit] != 1.0:
        loaded.apply_scale(UNIT_TO_MM[unit])
    return loaded
