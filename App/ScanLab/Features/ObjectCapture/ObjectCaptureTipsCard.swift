import SwiftUI

/// What decides photogrammetry quality, shown before capture starts. Most "broken" models come from
/// the object itself (glass, chrome, plain black) rather than the reconstruction.
struct ObjectCaptureTipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("İyi bir model için").font(.headline)
            Label("Şeffaf, parlak veya düz siyah yüzeyler (cam, krom, ayna) taranamaz. Mat tarama spreyi, kuru şampuan ya da talk pudrası ile matlaştır.",
                  systemImage: "sparkles")
            Label("Düz, desenli bir zemin ve gölgesiz, dağınık ışık kullan; nesnenin etrafını boşalt.",
                  systemImage: "lightbulb")
            Label("3 tur at: alçak, orta ve yüksek açıdan. Sonra ters çevirip alt yüzü de çek. En az 60 fotoğraf.",
                  systemImage: "arrow.triangle.2.circlepath")
        }
        .font(.footnote)
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}
