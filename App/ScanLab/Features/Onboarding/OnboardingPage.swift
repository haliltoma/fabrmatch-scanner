struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let body: String

    /// FR-1.4: technique, difficult surfaces, battery/heat.
    static let all: [OnboardingPage] = [
        .init(id: 0, systemImage: "figure.walk.motion", title: "Yavaş ve örtüşerek tara",
              body: "Telefonu yavaşça hareket ettir, her alanı birkaç açıdan gör. Boşluklar ekranda vurgulanır."),
        .init(id: 1, systemImage: "sparkles.rectangle.stack", title: "Zor yüzeyler",
              body: "Ayna, cam, çok parlak veya siyah yüzeylerde derinlik hatalı olabilir. Gerekirse o bölgeyi silip yeniden tara."),
        .init(id: 2, systemImage: "thermometer.medium", title: "Pil ve ısı",
              body: "Uzun taramalar cihazı ısıtır. Isı kritik seviyeye ulaşırsa tarama otomatik kaydedilip durdurulur."),
    ]
}
