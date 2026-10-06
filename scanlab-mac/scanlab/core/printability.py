"""`print_check`: FDM printability report (PRD M14 FR-14.1, M26 stage 6) for a mesh as it will sit
on the bed (z up). Each issue has a severity: `error` blocks printing, `warning` needs a decision."""

from __future__ import annotations

import math

import numpy as np
import trimesh

from .analyze import analyze
from .printer import Material, PrinterProfile

# Faces within the first two layers above the lowest point are carried by the first layers. Scanned
# bottoms are noisy (the lowest vertex sits ~4σ below the mean), so a tight geometric tolerance
# would wrongly report "no bed contact" and count the base itself as overhang.
DEFAULT_BED_TOLERANCE_MM = 0.4
# Bed faces may tilt this much (noise) and still count as resting on the bed.
BED_NORMAL_Z = -0.95


def _on_bed(mesh: trimesh.Trimesh, tolerance: float) -> np.ndarray:
    z_min = mesh.bounds[0, 2]
    return (mesh.face_normals[:, 2] < BED_NORMAL_Z) & (mesh.triangles[:, :, 2].max(axis=1) <= z_min + tolerance)


def overhang_faces(mesh: trimesh.Trimesh, overhang_angle_deg: float,
                   bed_tolerance_mm: float = DEFAULT_BED_TOLERANCE_MM) -> np.ndarray:
    """Down-facing faces steeper than the printer's overhang limit, excluding faces resting on the bed."""
    limit = math.cos(math.radians(90 - overhang_angle_deg))
    down = mesh.face_normals[:, 2] < -limit
    return down & ~_on_bed(mesh, bed_tolerance_mm)


def bed_contact_area(mesh: trimesh.Trimesh, bed_tolerance_mm: float = DEFAULT_BED_TOLERANCE_MM) -> float:
    return float(mesh.area_faces[_on_bed(mesh, bed_tolerance_mm)].sum())


def bed_tolerance(profile: PrinterProfile) -> float:
    return 2 * profile.layer_height_mm


def print_check(mesh: trimesh.Trimesh, profile: PrinterProfile, material: Material) -> dict:
    metrics = analyze(mesh)
    issues: list[dict] = []

    def issue(severity: str, code: str, message: str, **data) -> None:
        issues.append({"severity": severity, "code": code, "message": message, **data})

    if not metrics["watertight"]:
        issue("error", "not_watertight", f"{metrics['holes']} açık sınır döngüsü var; dilimleyici hacmi doğru göremez.",
              holes=metrics["holes"])
    if not metrics["manifold"]:
        issue("error", "non_manifold", f"{metrics['non_manifold_edges']} manifold olmayan kenar.")
    if metrics["inward_normals"]:
        issue("error", "inverted", "Normaller içe dönük (mesh_repair mode=normals).")
    if metrics["components"] > 1:
        issue("warning", "multiple_bodies", f"{metrics['components']} ayrı gövde; kopuk parçalar mı kasıtlı mı?")

    size = np.asarray(metrics["bbox_size"])
    vol = np.asarray(profile.build_volume_mm)
    fits_as_is = bool((size <= vol).all())
    fits_rotated = bool((np.sort(size[:2]) <= np.sort(vol[:2])).all() and size[2] <= vol[2])
    if not fits_as_is:
        issue("error" if not fits_rotated else "warning", "build_volume",
              f"Boyut {size.round(1).tolist()} mm, tabla hacmi {list(profile.build_volume_mm)} mm.",
              fits_after_z_rotation=fits_rotated)

    thickness = metrics.get("wall_thickness")
    if thickness and thickness["p5_mm"] < profile.min_wall_mm:
        issue("warning", "thin_walls", f"Duvarların %5'i {thickness['p5_mm']:.2f} mm'den ince; "
              f"{profile.name} için en az {profile.min_wall_mm} mm önerilir.", min_mm=thickness["min_mm"])
    if size.min() < profile.min_feature_mm:
        issue("error", "too_small", f"En küçük boyut {size.min():.2f} mm, nozul ile basılamaz.")

    over = overhang_faces(mesh, profile.overhang_angle_deg, bed_tolerance(profile))
    overhang_area = float(mesh.area_faces[over].sum())
    if overhang_area > 0.01 * mesh.area:
        issue("warning", "overhangs", f"{overhang_area:.0f} mm² yüzey {profile.overhang_angle_deg}°'den dik çıkıntı; "
              "destek gerekebilir veya yönü değiştir (print_orient_optimize).", area_mm2=round(overhang_area, 1))

    contact = bed_contact_area(mesh, bed_tolerance(profile))
    if contact < profile.min_bed_contact_mm2:
        issue("warning", "small_bed_contact", f"Tablaya temas {contact:.0f} mm²; yapışma zayıf olabilir "
              f"(öneri ≥ {profile.min_bed_contact_mm2} mm², brim veya düz taban).", contact_mm2=round(contact, 1))

    strict = float(mesh.area_faces[_on_bed(mesh, 0.05)].sum())
    if contact >= profile.min_bed_contact_mm2 and strict < 0.5 * contact:
        issue("warning", "rough_base", f"Taban pürüzlü: tablaya tam oturan alan {strict:.0f} mm² / {contact:.0f} mm². "
              "Dilimleyici ilk katmanı boş görebilir; print_flatten_base önerilir.", flat_mm2=round(strict, 1))

    if not profile.calibrated:
        issue("info", "uncalibrated", "Delik/fil ayağı telafisi kalibre edilmemiş varsayılanlar; kritik ölçüler için "
              "kalibrasyon baskısı önerilir.")

    volume_cm3 = (metrics["volume_mm3"] or 0) / 1000
    return {
        "printer": profile.name, "material": material.name,
        "printable": not any(i["severity"] == "error" for i in issues),
        "issues": issues,
        "summary": {
            "size_mm": size.round(2).tolist(), "volume_cm3": round(volume_cm3, 3),
            "solid_mass_g": round(volume_cm3 * material.density_g_cm3, 2),
            "overhang_area_mm2": round(overhang_area, 1), "bed_contact_mm2": round(contact, 1),
            "wall_thickness": thickness,
            "shrinkage_note": f"{material.name} tipik çekme ≈ %{material.shrinkage_pct}",
        },
    }
