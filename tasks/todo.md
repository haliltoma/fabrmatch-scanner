# Görevler — F0 + F1

Doğrulama komutu (paket): `scripts/test.sh`
Doğrulama komutu (uygulama, Xcode gerekir): `xcodegen && xcodebuild -scheme ScanLab -destination 'generic/platform=iOS' build`

## T1: SPM paketi + test betiği + ADR'ler — S
- [ ] `Packages/ScanLabKit` Swift 6 dil modunda derleniyor (iOS 18 / macOS 15)
- [ ] `scripts/test.sh` Xcode'suz (CLT) Swift Testing koşturuyor
- [ ] ADR-0001..0003 `docs/adr/` altında
Bağımlılık: yok

## T2: Çekirdek modeller — S
- [ ] `Project`/`ScanRecord` PRD §5.2 `project.json` şemasıyla birebir JSON gidiş-dönüşü
- [ ] `CaptureMode` protokolü PRD §4.3 sözleşmesiyle; `ScanArtifact` yalnızca dosya URL'leri taşır
- [ ] `Capability` + mod gereksinimleri; desteklenmeyen mod için okunabilir neden (FR-1.2)
Bağımlılık: T1

## T3: ProjectStore — M
- [ ] PRD §5.1 klasör yapısı oluşturuluyor; yazmalar atomik (FR §5.3)
- [ ] Çöp kutusu: silinen proje 30 gün tutulur, süresi dolan temizlenir (FR-2.3, FR-17.4)
- [ ] Yeniden adlandırma, çoğaltma, depolama özeti (ham/işlenmiş) (FR-2.6); serbest alan < 1 GB uyarısı
Bağımlılık: T2

## T4: MeshChunk + codec + MeshStore — M
- [ ] Chunk ikili kodlama gidiş-dönüşü kayıpsız; bozuk dosya hata verir (çökmez)
- [ ] `MeshStore` eski sürümlü güncellemeyi yok sayar (PRD M23 notu), silme ve anlık görüntü
- [ ] `flush(to:)` ile `raw/mesh_chunks/*.bin` ara kayıt (çökme kurtarma)
Bağımlılık: T2

## Kontrol noktası F0-a
- [ ] `scripts/test.sh` yeşil

## T5: Mesh birleştirme — S
- [ ] Chunk'lar dünya koordinatına dönüştürülür; ortak kenarlar 5 mm toleransla kaynaşır
- [ ] Dejenere (sıfır alan / tekrarlı indeks) üçgenler atılır; bbox doğru
Bağımlılık: T4

## T6: Dışa aktarıcılar — M
- [ ] STL ikili (80+4+50·n bayt), PLY ikili LE (renk opsiyonel), OBJ (akışla)
- [ ] Birim (m/cm/mm) ve eksen (Y-up/Z-up) seçenekleri (FR-13.1)
- [ ] Gidiş-dönüş doğrulama: üçgen sayısı ve bbox eşit (FR-13.5)
Bağımlılık: T5

## T7: Sensör seçici — S
- [ ] PRD M22 karar tablosunun her satırı parametreli testle doğrulanır
- [ ] Öneri gerekçe metni + güven değeri içerir; sensör profili eşikleri değiştirir (FR-22.5)
Bağımlılık: T2

## T8: Termal politika — XS
- [ ] nominal/fair → devam, serious → uyarı, critical → ara kayıt + durdur (FR-3.8)
Bağımlılık: T2

## Kontrol noktası F0-b
- [ ] Tüm paket testleri yeşil, uyarısız derleme

## T9: iOS uygulama iskeleti — M (Xcode'da doğrulanacak)
- [ ] `project.yml` → ScanLab hedefi, iOS 18, paket bağımlılığı, Info.plist izinleri (kamera, foto, yerel ağ)
- [ ] Açılışta yetenek kontrolü (FR-1.1); LiDAR'sız cihazda çökmez, modlar gri + neden
- [ ] 3 ekranlık onboarding (FR-1.4)

## T10: Kütüphane ekranı — M
- [ ] Liste, arama (ad/etiket), sıralama (tarih/ad/boyut), yeniden adlandır, sil→çöp kutusu

## T11: LiDAR capture modu + tarama ekranı — L
- [ ] PRD M3 yapılandırması; `ARMeshAnchor` → `MeshStore` (delegate'te ağır iş yok)
- [ ] HUD: süre, üçgen sayısı, takip durumu mesajları (FR-3.4), termal uyarı; 10 sn ara kayıt
- [ ] Başlat/Duraklat/Devam/Bitir; `isIdleTimerDisabled` tarama sırasında

## T12: Kayıt + dışa aktarma — M
- [ ] Bitir → chunk'lar + `scan.json` diske, projeye eklenir
- [ ] Dışa aktarma sayfası: format/birim/eksen → `exports/` → paylaşım menüsü

## Kontrol noktası F1 (İNSAN)
- [ ] Xcode kur, `xcodegen`, cihazda derle
- [ ] M3 kabul: oda taraması diske eksiksiz yazılıyor, yeniden açılıyor; 5 dk taramada bellek < %70
