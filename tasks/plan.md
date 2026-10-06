# Uygulama Planı: ScanLab (fabrmatch-scanner)

Kaynak: `docs/3D-Tarayici-PRD.md` (v1.0). Bu plan PRD'nin **F0 + F1** fazlarını görev görev açar;
sonraki fazlar (F2…F7) yalnızca indeks olarak listelenir ve F1 kapanınca ayrıntılandırılır
(PRD §12 "kapsam şişmesi" riski: F1 bitmeden F2'ye geçilmez).

## Genel bakış
Native iOS (Swift 6.2 / SwiftUI) LiDAR tarayıcı. İlk kullanılabilir sürüm (F1): LiDAR mesh taraması,
canlı önizleme, diske kayıt, OBJ/PLY/STL dışa aktarma, proje kütüphanesi.

## Mimari kararlar
- **ADR-0001 — Platformdan bağımsız çekirdek SPM paketi (`Packages/ScanLabKit`).** Model, depolama,
  MeshStore, mesh birleştirme, dışa aktarıcılar ve sensör seçimi ARKit/UIKit'e bağımlı değildir;
  macOS'ta `swift test` ile doğrulanır. ARKit/RealityKit kodu yalnızca uygulama hedefindedir.
- **ADR-0002 — Xcode projesi XcodeGen ile (`project.yml`).** `.pbxproj` elle yazılmaz / sürüm kontrolünde
  çakışma üretmez. Kurulum: `brew install xcodegen && xcodegen`.
- **ADR-0003 — Eşzamanlılık.** Paket: Swift 6 dil modu, varsayılan izolasyon yok (nonisolated);
  paylaşılan durum `actor` (`MeshStore`, `ProjectStore`). Uygulama: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
  ARKit delegate'i ağır iş yapmaz, `Sendable` değer tipleri (`MeshChunk`) ile `MeshStore`'a aktarır (PRD §4.4).
- **Testler:** Swift Testing (`#expect`/`#require`, parametreli testler). `scripts/test.sh` CLT ile çalıştırır.
- **Üçüncü taraf bağımlılık yok** (F1). meshoptimizer/xatlas/Poisson F3'te ayrı ADR ile eklenir.

## Ortam durumu (2026-10-07)
- macOS 27.0.1, Swift 6.2.4 (Command Line Tools). **Xcode kurulu değil** → iOS hedefi bu makinede
  derlenemez/cihaza yüklenemez. Paket testleri çalışır.
- Python 3.9.6 (sistem). Mac köprüsü (F2b/F3b) Python 3.12 ister → `brew install python@3.12`.

## Görev listesi
Ayrıntılı kabul ölçütleri: `tasks/todo.md`.

### Faz F0 — Temel
- [x] T1: SPM paketi + test betiği + ADR'ler
- [x] T2: Çekirdek modeller (Project/Scan, Capability, CaptureMode sözleşmesi)
- [x] T3: `ProjectStore` (atomik yazma, klasör yapısı, çöp kutusu 30 gün, disk kontrolü)
- [x] T4: `MeshChunk` + ikili codec + `MeshStore` actor (sürüm korumalı upsert)
### Kontrol noktası F0-a: `scripts/test.sh` yeşil ✅
- [x] T5: Mesh birleştirme (dünya koordinatı + 5 mm weld + dejenere üçgen temizliği)
- [x] T6: Dışa aktarıcılar STL/PLY/OBJ + gidiş-dönüş doğrulama (FR-13.5)
- [x] T7: Kural tabanlı sensör seçici (M22 karar tablosu)
- [x] T8: Termal politika (FR-3.8)
### Kontrol noktası F0-b: tüm paket testleri yeşil ✅ (38 test / 10 suite)
- [~] T9: iOS uygulama iskeleti (XcodeGen, Info.plist izinleri, yetenek kontrolü, onboarding)
- [~] T10: Kütüphane ekranı (liste, arama, sıralama, yeniden adlandır, çöp kutusu)
- [~] T11: LiDAR capture modu + AR tarama ekranı + HUD
- [~] T12: Tarama sonu kayıt + dışa aktarma paylaşımı
`[~]` = kod yazıldı, Xcode olmadığı için **derlenmedi / cihazda denenmedi**.

### Kontrol noktası F1 (İNSAN): Xcode kurulumu, `xcodegen`, cihazda derleme + PRD M3 kabul testleri

### Faz F0b — FreeCAD MCP ✅ (2026-10-07, bkz. `docs/environment.md`)
- [x] Sürüm kaydı, güvenlik incelemesi, 5 adımlı duman testi (`scanlab-mac/freecad_bridge/smoke_test_f0b.py`)
- [x] FreeCAD eklentisi freecad-mcp 0.1.25 ile eşlendi (eski sürüm yedeklendi)

### Faz F3b — Mac geometri motoru + `scanlab-mcp` (PRD §4.7, M25)
Ayrım (PRD §4.7): `scanlab/core` MCP'den bağımsız; `scanlab/mcp_server` ince kabuk.
- [x] B1: uv projesi (Python 3.12, arm64 tekerlekler: trimesh, numpy, scipy, pymeshfix, manifold3d, matplotlib, mcp) + pytest
- [x] B2: Depo + sürüm ağacı (SQLite + dosya; her işlem yeni sürüm, orijinal asla ezilmez, `version_revert`)
- [x] B3: İçe aktarma: STL/PLY/OBJ/GLB + iPhone `mesh_chunks/*.bin` (SLMC v1, Swift ile ortak altın dosya testi)
- [x] B4: `mesh_analyze` (bbox, sayılar, watertight, manifold, delik/sınır döngüsü, bileşen, dejenere, hacim/alan, duvar kalınlığı tahmini)
- [x] B5: Onarım/temizlik: küçük bileşen silme, delik doldurma, tam onarım (pymeshfix); `dry_run` + `max_deviation_mm`
- [x] B6: `deviation_compare` (Chamfer/Hausdorff/%95) + `mesh_render_views` (çok açılı PNG, GPU'suz)
- [x] B7: Dışa aktarma STL/PLY/OBJ/GLB/3MF → `cad_exchange/out`
- [x] B8: MCP sunucusu (stdio): araçlar + kaynaklar + `inspect_scan_quality` / `make_print_ready` prompt'ları; yol kısıtı, kod çalıştırma yok
### Kontrol noktası F3b ✅ (39 pytest + stdio e2e): pytest yeşil; MCP üzerinden `mesh_analyze → mesh_repair → mesh_analyze` zinciri sürüm geçmişine yazılır (M25 kabul)

### Faz F5b — Baskıya hazırlama hattı (M14, M26, M27) · Yazıcı: Creality K2 Pro
Kaynak: OrcaSlicer 2.4.2 hazır profili `Creality K2 Pro 0.4 nozzle` (300×300×300 mm, 0,4 sertleştirilmiş çelik, Klipper).
- [x] P1: Yazıcı profili (YAML) + yükleyici; FDM varsayılanları PRD §2.1, malzeme→Orca filament eşlemesi
- [x] P2: `print_check` (watertight/manifold, tabla hacmine sığma, min duvar, ince detay, çıkıntı alanı, tabla temas alanı)
- [x] P3: `print_orient_optimize` (eksen + gövde yüzeyi adayları, puanlama, tablaya oturtma → yeni sürüm)
- [x] P4: `print_slice_dry_run` (OrcaSlicer CLI, profil düzleştirme, delik/fil ayağı telafisi, G-code'dan süre/filament)
- [x] P5: MCP araçları + `scanlab://printers` + `make_print_ready` prompt'unun yazıcıya bağlanması
- [x] P6b: `print_flatten_base` (FR-14.4) — benchmark'ta gürültülü tabanın OrcaSlicer'ı düşürdüğü bulundu
- [x] P6: Ajan playbook'u (M26 §26.7) + 5 parçalık benchmark (düz plaka, delikli braket, mil, ince duvarlı kutu, organik tutamak) ve sabit hat sonuç tablosu
### Kontrol noktası F5b — sabit hat ✅ 5/5 (`scanlab-mac/benchmarks/results.md`), ajan denemesi bekliyor: benchmark'ta 5 parça watertight + dilimleme provası başarılı; gerçek Claude oturumunda ajan denemesi (İNSAN)

### Sonraki fazlar (indeks)
F2 viewer/ölçüm/not · F2b Mac köprüsü · F3 mesh işleme + GLB + baskı ·
F3b Python geometri motoru + MCP · F4 RoomPlan/ObjectCapture/nokta bulutu/TrueDepth ·
F5 doku/AR/web/iCloud · F5b ajan · F5c FreeCAD · F6 splat/hibrit.

## Riskler
| Risk | Etki | Azaltma |
|---|---|---|
| Uygulama hedefi bu makinede derlenemiyor | Yüksek | Mantığın tamamı test edilen pakette; uygulama katmanı ince tutuldu; F1 kontrol noktasında Xcode ile derleme |
| ARKit API farkları (iOS 26) | Orta | Yalnızca uzun süredir kararlı API'ler (`ARMeshAnchor`, `ARView`) kullanıldı |
| Bellek (uzun tarama) | Yüksek | Chunk bazlı depo, ara kayıt (10 sn), termal politika |

## Açık sorular (PRD §13'ten, F1'i bloklamayanlar)
1. Xcode sürümü / Apple Developer hesabı (imza için Team ID → `project.yml`'deki `DEVELOPMENT_TEAM`).
2. Asıl kullanım önceliği (F2–F4 sırasını belirler).
3. Yazıcı modeli, tolerans, FreeCAD MCP sunucusu (F0b/F5b/F5c).
