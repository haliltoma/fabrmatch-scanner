# ADR-0003: Eşzamanlılık modeli

- Durum: Kabul edildi — 2026-10-07

## Karar
- Paket: Swift 6 dil modu (tam veri yarışı denetimi), varsayılan izolasyon yok. Paylaşılan değişken
  durum `actor` içinde (`MeshStore`, `ProjectStore`). Sınırı geçen veriler `Sendable` değer tipleri.
- Uygulama: varsayılan izolasyon `MainActor` (UI). `ARSessionDelegate` geri çağrıları yalnızca
  `MeshChunk` kopyası üretir ve `MeshStore`'a `Task` ile iletir (PRD §4.4); ağır işler (birleştirme,
  dışa aktarma) `@concurrent` async fonksiyonlarda.
- `@unchecked Sendable` / `nonisolated(unsafe)` yalnızca belgelenmiş değişmezle.
