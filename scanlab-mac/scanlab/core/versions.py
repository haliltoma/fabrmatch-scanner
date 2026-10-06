"""Project + version tree (PRD §4.7 core/versions, M25 rule 1: every tool creates a new version).

Mesh files are immutable once written; the database only ever appends versions and
moves a project's `head` pointer, so any earlier state can be restored.
"""

from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import trimesh

from .workspace import Workspace

_SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    head TEXT
);
CREATE TABLE IF NOT EXISTS versions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    parent_id TEXT REFERENCES versions(id),
    tool TEXT NOT NULL,
    params TEXT NOT NULL,
    metrics TEXT NOT NULL,
    file TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS versions_project ON versions(project_id, created_at);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    detail TEXT NOT NULL,
    created_at TEXT NOT NULL
);
"""


class NotFound(KeyError):
    pass


@dataclass(frozen=True)
class Version:
    id: str
    project_id: str
    parent_id: str | None
    tool: str
    params: dict
    metrics: dict
    file: Path
    created_at: str

    def summary(self) -> dict:
        return {"id": self.id, "parent_id": self.parent_id, "tool": self.tool, "params": self.params,
                "metrics": self.metrics, "created_at": self.created_at}


@dataclass(frozen=True)
class Project:
    id: str
    name: str
    created_at: str
    head: str | None


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


class VersionStore:
    def __init__(self, workspace: Workspace):
        self.ws = workspace
        self.db = sqlite3.connect(workspace.database, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(_SCHEMA)

    # Projects
    def create_project(self, name: str) -> Project:
        name = name.strip()
        if not name:
            raise ValueError("project name must not be empty")
        p = Project(uuid.uuid4().hex[:12], name, _now(), None)
        with self.db:
            self.db.execute("INSERT INTO projects VALUES (?,?,?,?)", (p.id, p.name, p.created_at, None))
        (self.ws.projects_dir / p.id / "versions").mkdir(parents=True, exist_ok=True)
        return p

    def project(self, project_id: str) -> Project:
        row = self.db.execute("SELECT * FROM projects WHERE id=?", (project_id,)).fetchone()
        if row is None:
            raise NotFound(f"project {project_id}")
        return Project(row["id"], row["name"], row["created_at"], row["head"])

    def projects(self) -> list[Project]:
        rows = self.db.execute("SELECT * FROM projects ORDER BY created_at DESC").fetchall()
        return [Project(r["id"], r["name"], r["created_at"], r["head"]) for r in rows]

    # Versions
    def add_version(self, project_id: str, mesh: trimesh.Trimesh, tool: str, params: dict,
                    metrics: dict, parent_id: str | None) -> Version:
        self.project(project_id)
        vid = uuid.uuid4().hex[:12]
        path = self.ws.projects_dir / project_id / "versions" / f"{vid}.ply"
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(mesh.export(file_type="ply", encoding="binary"))
        tmp.replace(path)
        v = Version(vid, project_id, parent_id, tool, params, metrics, path, _now())
        with self.db:
            self.db.execute("INSERT INTO versions VALUES (?,?,?,?,?,?,?,?)",
                            (v.id, project_id, parent_id, tool, json.dumps(params), json.dumps(metrics),
                             str(path), v.created_at))
            self.db.execute("UPDATE projects SET head=? WHERE id=?", (vid, project_id))
        return v

    def version(self, version_id: str) -> Version:
        row = self.db.execute("SELECT * FROM versions WHERE id=?", (version_id,)).fetchone()
        if row is None:
            raise NotFound(f"version {version_id}")
        return self._version(row)

    def versions(self, project_id: str) -> list[Version]:
        rows = self.db.execute("SELECT * FROM versions WHERE project_id=? ORDER BY rowid", (project_id,)).fetchall()
        return [self._version(r) for r in rows]

    def head(self, project_id: str) -> Version:
        head = self.project(project_id).head
        if head is None:
            raise NotFound(f"project {project_id} has no versions")
        return self.version(head)

    def resolve(self, project_id: str, version_id: str | None) -> Version:
        """`version_id` or the project head; the version must belong to the project."""
        v = self.version(version_id) if version_id else self.head(project_id)
        if v.project_id != project_id:
            raise NotFound(f"version {v.id} is not in project {project_id}")
        return v

    def revert(self, project_id: str, version_id: str) -> Version:
        v = self.resolve(project_id, version_id)
        with self.db:
            self.db.execute("UPDATE projects SET head=? WHERE id=?", (v.id, project_id))
        self.log(project_id, "revert", {"head": v.id})
        return v

    def load(self, version: Version) -> trimesh.Trimesh:
        return trimesh.load_mesh(version.file, process=False)

    def log(self, project_id: str, kind: str, detail: dict) -> None:
        with self.db:
            self.db.execute("INSERT INTO events (project_id, kind, detail, created_at) VALUES (?,?,?,?)",
                            (project_id, kind, json.dumps(detail), _now()))

    def events(self, project_id: str) -> list[dict]:
        rows = self.db.execute("SELECT kind, detail, created_at FROM events WHERE project_id=? ORDER BY id",
                               (project_id,)).fetchall()
        return [{"kind": r["kind"], "detail": json.loads(r["detail"]), "created_at": r["created_at"]} for r in rows]

    @staticmethod
    def _version(r: sqlite3.Row) -> Version:
        return Version(r["id"], r["project_id"], r["parent_id"], r["tool"], json.loads(r["params"]),
                       json.loads(r["metrics"]), Path(r["file"]), r["created_at"])
