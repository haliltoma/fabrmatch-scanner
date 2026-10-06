"""`mesh_render_views`: multi-angle shaded PNGs without a GPU (matplotlib Agg), for the agent's
visual check (M26 §26.3)."""

from __future__ import annotations

import io

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import trimesh  # noqa: E402
from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: E402

VIEWS: dict[str, tuple[float, float]] = {
    "iso": (30, -60), "iso_back": (30, 120), "front": (0, -90), "back": (0, 90),
    "left": (0, 180), "right": (0, 0), "top": (90, -90), "bottom": (-90, -90),
}
MAX_RENDER_FACES = 30_000


def render_views(mesh: trimesh.Trimesh, views: list[str] | None = None, size_px: int = 512,
                 heatmap: np.ndarray | None = None, wireframe: bool = False) -> list[tuple[str, bytes]]:
    """Returns (view_name, png_bytes). `heatmap` is an optional per-face scalar (e.g. deviation mm)."""
    views = views or ["iso", "front", "top", "right"]
    unknown = [v for v in views if v not in VIEWS]
    if unknown:
        raise ValueError(f"unknown views {unknown}; choose from {sorted(VIEWS)}")
    m = mesh
    if len(m.faces) > MAX_RENDER_FACES and heatmap is None:
        m = m.simplify_quadric_decimation(face_count=MAX_RENDER_FACES)
    tris = m.vertices[m.faces]
    light = np.array([0.4, -0.5, 0.75])
    light /= np.linalg.norm(light)
    shade = np.clip(np.abs(m.face_normals @ light), 0.15, 1.0)
    if heatmap is not None:
        norm = plt.Normalize(vmin=0, vmax=max(float(np.max(heatmap)), 1e-9))
        colors = plt.cm.turbo(norm(heatmap))
    else:
        base = np.array([0.55, 0.62, 0.70])
        colors = np.c_[shade[:, None] * base, np.ones(len(shade))]
    center, extent = m.bounds.mean(axis=0), float(m.extents.max()) / 2 or 1.0

    out = []
    for name in views:
        fig = plt.figure(figsize=(size_px / 100, size_px / 100), dpi=100)
        ax = fig.add_subplot(projection="3d", computed_zorder=False)
        ax.add_collection3d(Poly3DCollection(tris, facecolors=colors, edgecolors=(0, 0, 0, 0.25) if wireframe else "none",
                                             linewidths=0.2))
        for setter, c in zip((ax.set_xlim, ax.set_ylim, ax.set_zlim), center):
            setter(c - extent, c + extent)
        ax.set_box_aspect((1, 1, 1))
        elev, azim = VIEWS[name]
        ax.view_init(elev=elev, azim=azim)
        ax.set_axis_off()
        ax.set_title(name, fontsize=8)
        buf = io.BytesIO()
        fig.savefig(buf, format="png", bbox_inches="tight", pad_inches=0.05)
        plt.close(fig)
        out.append((name, buf.getvalue()))
    return out
