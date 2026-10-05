import SwiftUI

/// claude.ai's page (`GlassWebCard`, made once by the view model) inside the glass card.
struct GlassPage: NSViewRepresentable {
    let card: GlassWebCard

    func makeNSView(context: Context) -> GlassWebCard {
        card
    }

    func updateNSView(_ nsView: GlassWebCard, context: Context) {}
}
