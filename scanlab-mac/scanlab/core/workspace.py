"""Workspace layout and path policy (PRD §4.7, M25 security: paths limited to the project store)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


class PathNotAllowed(ValueError):
    """Raised when a caller-supplied path falls outside the allowed roots."""


@dataclass(frozen=True)
class Workspace:
    home: Path
    exchange: Path

    @classmethod
    def from_env(cls) -> "Workspace":
        home = Path(os.environ.get("SCANLAB_HOME", Path.home() / "ScanLab")).expanduser()
        exchange = Path(os.environ.get("SCANLAB_EXCHANGE", home / "cad_exchange")).expanduser()
        return cls.create(home, exchange)

    @classmethod
    def create(cls, home: Path, exchange: Path | None = None) -> "Workspace":
        ws = cls(home.resolve(), (exchange or home / "cad_exchange").resolve())
        for d in (ws.projects_dir, ws.inbox, ws.outbox, ws.exchange / "params", ws.reports):
            d.mkdir(parents=True, exist_ok=True)
        return ws

    @property
    def projects_dir(self) -> Path:
        return self.home / "projects"

    @property
    def database(self) -> Path:
        return self.home / "scanlab.db"

    @property
    def inbox(self) -> Path:
        return self.exchange / "in"

    @property
    def outbox(self) -> Path:
        return self.exchange / "out"

    @property
    def reports(self) -> Path:
        return self.exchange / "reports"

    def resolve_input(self, path: str | Path) -> Path:
        """Accepts only existing files under the exchange inbox or the workspace home.

        Relative paths are resolved against the inbox. Symlinks are resolved first,
        so a link pointing outside the allowed roots is rejected.
        """
        p = Path(path).expanduser()
        if not p.is_absolute():
            p = self.inbox / p
        p = p.resolve()
        if not any(p.is_relative_to(root) for root in (self.inbox, self.home)):
            raise PathNotAllowed(f"path outside allowed roots: {p}")
        if not p.exists():
            raise FileNotFoundError(p)
        return p

    def resolve_output(self, filename: str) -> Path:
        """Output files may only be written directly into the exchange outbox."""
        name = Path(filename).name
        if not name or name != filename or name.startswith("."):
            raise PathNotAllowed(f"output must be a plain file name, got {filename!r}")
        return self.outbox / name
