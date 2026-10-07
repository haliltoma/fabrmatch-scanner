# Ortam kaydı (PRD M28 §28.9 — F0b)

Son doğrulama: 2026-10-07 · Sonuç: **GEÇTİ (5/5)** · Rapor: `scanlab-mac/cad_exchange/reports/f0b_smoke.json`

## Sürümler (sabitlenmiş)
| Bileşen | Sürüm | Not |
|---|---|---|
| macOS | 27.0.1 (Apple Silicon) | |
| FreeCAD | 1.1.3, build 20260725, arm64 yerel | `/Applications/FreeCAD.app` |
| FreeCAD eklentisi | `FreeCADMCP` **0.1.25**, protokol 1 (neka-nat/freecad-mcp etiket `v0.1.25`, commit `d6bbe4b`) | `~/Library/Application Support/FreeCAD/v1-1/Mod/FreeCADMCP`; eski sürümün yedeği `…/v1-1/FreeCADMCP.backup-20261007-005125` |
| MCP sunucusu | `freecad-mcp==0.1.25` (PyPI, `uvx`) | Claude Code: proje `.mcp.json`; Claude Desktop: `claude_desktop_config.json` — ikisi de `==0.1.25` ile sabit |
| RPC köprüsü | XML-RPC `127.0.0.1:9875`, `remote_enabled=false`, `allowed_ips=127.0.0.1`, `auto_start_rpc=true` | |
| Dilimleyici | OrcaSlicer **2.4.2** (`/Applications/OrcaSlicer.app`), başsız CLI dilimleme doğrulandı (`--slice 0 --load-settings machine;process --load-filaments`), sistem profilleri `inherits` zinciri düzleştirilerek kullanılıyor; hata ayrıntısı CLI'da yalnızca "run found error"; Claude Desktop'ta `orcaslicer-mcp` de tanımlı | PRD'deki PrusaSlicer/Cura yerine |
| Swift | 6.2.4 (yalnızca Command Line Tools, Xcode yok) | iOS hedefi derlenemiyor |

## Güvenlik incelemesi (PRD §28.7)
- Eklenti: dinleme adresi ayar kapalıyken `127.0.0.1`; IP filtresi var. 0.1.25 isteğe bağlı auth token (`Set Auth Token` menüsü / `FREECAD_MCP_TOKEN`) ve web sayfası kaynaklı isteklerin reddini ekler. Token şu an boş (yalnızca localhost'a güveniliyor).
- Serbest kod: `execute_code`, `execute_code_async` (GUI, `exec`) ve `execute_code_headless` (`freecadcmd` alt süreci). Claude Code'da bu araçlar **izin istemeli** — `allow` listesine eklemeyin.
- MCP paketi: dış ağ çağrısı yok; yalnızca localhost XML-RPC ve yerel `freecadcmd`.

## Duman testi (tekrar çalıştırma)
```
# FreeCAD açık ve MCP eklentisi RPC sunucusu çalışıyor olmalı
uvx --from freecad-mcp==0.1.25 python scanlab-mac/freecad_bridge/smoke_test_f0b.py
```
| Adım | Kontrol | Sonuç |
|---|---|---|
| 1 Kayıt | FreeCAD sürümü + RPC durumu okunur | ✅ |
| 2 Bağlantı | `ping`, GUI dispatch sağlıklı | ✅ |
| 3 Temel komut | 20×20×10 kutu − Ø5 delik: hacim 3803.650 mm³, bbox 20/20/10, delik r=2.5 | ✅ (ekran görüntüsü `reports/f0b_model.png`) |
| 4 İçe aktarma | `cad_exchange/in` STL (30×20×5): 12 yüz, 8 nokta, katı, hacim 3000 | ✅ |
| 5 Dışa aktarma | STEP geri okuma hacmi birebir; STL katı, hacim farkı %0.002; OrcaSlicer CLI açıp 592 üçgenle yeniden yazdı | ✅ |

## M28.2 / M28.6 için bulgular
- Araç adları (freecad-mcp 0.1.25): `create_document`, `create_object`, `edit_object`, `delete_object`, `get_objects`, `get_object`, `get_view`, `list_documents`, `reload_document`, `insert_part_from_library`, `get_parts_list`, `execute_code`, `execute_code_async`, `execute_code_headless`, `get_async_status`, `get_rpc_status`, `run_fem_analysis`.
- `create_object` boolean bağlantıları (Base/Tool) desteklemiyor; `Part::Cut` vb. için sabit şablon betik gerekli → kendi `cad_*` araçlarımız (Seçenek B) için gerekçe.
- FreeCAD 1.1'de `Part::Cut` sonucu `Compound` döner; doğrulamada `Shape.Solids` kullanılmalı.
- Açık konu: eklentiyi 0.1.25 ile eşleştirmek (sürüm uyarısı).

## Yazıcı
| | |
|---|---|
| Model | Creality K2 Pro, 0,4 mm sertleştirilmiş çelik nozul, Klipper |
| Tabla | 300 × 300 × 300 mm (OrcaSlicer preset `Creality K2 Pro 0.4 nozzle`) |
| Varsayılan işlem | `0.20mm Standard @Creality K2 Pro 0.4 nozzle` |
| Telafiler | delik 0,1 mm, fil ayağı 0,15 mm — **kalibre edilmedi** |
| Profil | `scanlab-mac/scanlab/core/printers/creality_k2_pro.yaml` |

## Yeniden yapılandırma bağımlılıkları
| | |
|---|---|
| Open3D | 0.20.0 (arm64) — TSDF (tensor `VoxelBlockGrid`), raycasting, mesafe. Homebrew `libusb` gerektirir (`brew install libusb`) |
| PyMeshLab | 2025.7.post1 — screened Poisson (Open3D'nin Poisson'u bu girdilerde süreci `abort()` ile düşürdü) |
| shapely, mapbox-earcut | taban kapatma üçgenlemesi |

## Object Capture fotoğraflarını Mac'te tam detayda işleme
Telefon yalnızca `.reduced` detay üretir. Proje ekranındaki "Fotoğrafları paylaş (ZIP)" ile fotoğrafları Mac'e at, aç ve:

    swift scanlab-mac/tools/photogrammetry.swift <images-klasörü> model.usdz full     # preview|reduced|medium|full|raw

Varsayılan: yüksek özellik hassasiyeti, sıralı eşleme, nesne maskeleme. 25 fotoğraflık şişe taramasında ~50 sn sürdü.
