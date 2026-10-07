# Rakip analizi — iPhone 3B tarama uygulamaları (Ekim 2026)

Amaç: piyasadaki en iyi uygulamaların özelliklerini ScanLab'a taşımak (PRD hedef 1).

## Özellik karşılaştırması

| Özellik | Polycam | Scaniverse | 3D Scanner App | KIRI Engine | ScanLab |
|---|---|---|---|---|---|
| LiDAR oda/sahne taraması | ✔ | ✔ | ✔ | ✔ | ✔ |
| TrueDepth (ön kamera) küçük nesne | – | – | ✔ | – | ✔ (ham kare + Mac'te çok algoritma) |
| Foto/Object Capture (dokulu model) | ✔ | ✔ | ✔ | ✔ (150 foto) | ✔ (cihazda fotogrametri) |
| Oda planı (RoomPlan) | ✔ | – | ✔ | ✔ | ✔ |
| 2B ölçülü kat planı (PDF/DXF) | ✔ PDF, DXF, CSV, PNG | – | ✔ DXF | ✔ | ✔ PDF · DXF ⏳ |
| Uygulama içi 3B görüntüleyici | ✔ | ✔ | ✔ | ✔ | ✔ (gölgeli/sınıf/tel kafes/nokta) |
| Mesafe ölçümü | ✔ | ✔ | ✔ cetvel | ✔ | ✔ (kalıcı) |
| Sınır kutusu ölçüleri | – | – | ✔ | – | ✔ |
| Cihazda kırpma/düzenleme | ✔ | ✔ | ✔ | ✔ | ✔ kutu kırpma |
| AR'da gerçek boyut önizleme | ✔ | ✔ | ✔ USDZ | ✔ | ✔ |
| Dışa aktarma: OBJ / STL / PLY / GLB / USDZ | ✔ (+FBX) | ✔ (+FBX, LAS) | ✔ (+DAE, LAS, PTS, PCD, XYZ) | ✔ | ✔ + XYZ · FBX/LAS ⏳ |
| Renkli (dokulu) LiDAR mesh | ✔ | ✔ | ✔ | ✔ | ⏳ (RGB kare kaydı gerekli) |
| Cihazda Gaussian Splat | – | ✔ (ücretsiz, cihazda) | – | ✔ (bulut) | ⏳ (paket var, eğitim PC/Mac'te) |
| Çok algoritmalı yeniden yapılandırma + en iyiyi seçme | – | – | – | AI rafine (bulut) | ✔ (Mac, kör seçici, benchmark'lı) |
| Çevir-hizala (alt yüzü tarama) | – | – | – | – | ✔ (Mac) |
| Baskıya hazırlama (FDM, dilimleme provası) | – | – | – | – | ✔ (Mac + MCP) |
| Abonelik / dışa aktarma ücreti | Pro ücretli | Ücretsiz | Ücretsiz/Pro | Ücretsiz katman + Pro | Yok (kişisel) |

✔ var · ⏳ yol haritasında · – yok

## Bu turda eklenenler
Proje açılınca canlı 3B model · tam ekran görüntüleyici (görünüm modları, sığdır) · kalıcı ölçüm · sınır kutusu ·
kutu kırpma (yeni PLY olarak kayıt) · AR Quick Look · GLB / USDZ / XYZ dışa aktarma · USDZ'den OBJ/STL/PLY dönüştürme ·
RoomPlan'dan ölçülü PDF kat planı · ham karelerin ZIP olarak Mac'e gönderimi · otomatik küçük resimler.

## Sonraki adaylar (öncelik sırasıyla)
1. Renkli LiDAR mesh: anahtar karelerde RGB kaydı + Mac'te/cihazda vertex-color/doku (M8).
2. DXF kat planı + kat planında kapı/pencere ölçüleri.
3. Cihazda mesh sadeleştirme (LOD) ve delik doldurma (M9).
4. Not/etiket (M12) ve PDF rapor.
5. FBX/LAS dışa aktarma.

## Kaynaklar
- [KIRI Engine — Best LiDAR 3D Scanner Apps for iPhone (2026)](https://www.kiriengine.app/blog/best-lidar-3d-scanner-apps-iphone-2026)
- [Polycam — floor plan pipeline](https://poly.cam/blog/how-we-turn-raw-spatial-data-into-a-floor-plan-you-can-build-from-inside-polycams-floor-plan-pipeline)
- [AEC Magazine — Polycam for AEC](https://aecmag.com/technology/polycam-for-aec/)
- [Scaniverse (Niantic Spatial)](https://nianticspatial.com/products/scaniverse)
- [Scaniverse — 3D Gaussian splatting support](https://cgpress.org/archives/scaniverse-introduces-support-for-3d-gaussian-splatting.html)
- [3d Scanner App — App Store](https://apps.apple.com/us/app/-/id1419913995)
- [Best Photogrammetry Apps 2026 — SkyeBrowse](https://www.skyebrowse.com/news/posts/best-photogrammetry-app)
