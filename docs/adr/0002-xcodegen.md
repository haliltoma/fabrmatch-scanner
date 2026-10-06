# ADR-0002: Xcode projesi XcodeGen ile üretilir

- Durum: Kabul edildi — 2026-10-07

## Karar
`project.yml` tek doğruluk kaynağıdır; `ScanLab.xcodeproj` üretilir ve `.gitignore`'dadır.

## Sonuçlar
+ Okunabilir, birleştirme çakışması olmayan proje tanımı; ajanlar güvenle düzenleyebilir.
− Geliştiricinin `brew install xcodegen` çalıştırması gerekir.
