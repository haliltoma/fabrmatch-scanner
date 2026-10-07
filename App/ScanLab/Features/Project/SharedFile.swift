import SwiftUI

struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
