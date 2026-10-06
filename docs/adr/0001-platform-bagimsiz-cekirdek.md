# ADR-0001: Platformdan bağımsız çekirdek SPM paketi

- Durum: Kabul edildi — 2026-10-07

## Bağlam
PRD §4 katmanlı mimari ister. Geliştirme makinesinde Xcode yok; iOS hedefi derlenemiyor. Mesh, depolama
ve dışa aktarma mantığı en çok hata çıkaracak ve en çok test gerektiren kısım.

## Karar
`Packages/ScanLabKit` paketi üç modülle: `ScanLabCore` (modeller, depolama, MeshStore, birleştirme,
termal politika), `ScanLabExport` (STL/PLY/OBJ), `ScanLabSensor` (M22 kural tabanlı seçici).
Bu modüller yalnızca Foundation + simd kullanır; ARKit/UIKit/RealityKit uygulama hedefinde kalır.

## Sonuçlar
+ macOS'ta `swift test` ile hızlı, cihazsız test; ileride Mac köprüsü de aynı kodu kullanabilir.
− ARKit tipleri (ARMeshAnchor) uygulama katmanında `MeshChunk`'a çevrilmeli (ince adaptör).
