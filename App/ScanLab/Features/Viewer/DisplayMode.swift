/// FR-10.2 display modes (the subset that applies to each content type is offered).
enum DisplayMode: String, CaseIterable, Identifiable {
    case shaded, classification, wireframe, points

    var id: Self { self }

    var title: String {
        switch self {
        case .shaded: "Gölgeli"
        case .classification: "Sınıflar"
        case .wireframe: "Tel kafes"
        case .points: "Noktalar"
        }
    }

    var systemImage: String {
        switch self {
        case .shaded: "cube.fill"
        case .classification: "paintpalette"
        case .wireframe: "cube.transparent"
        case .points: "circle.grid.3x3.fill"
        }
    }
}
