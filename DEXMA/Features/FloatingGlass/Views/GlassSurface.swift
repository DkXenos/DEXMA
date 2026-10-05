import SwiftUI

/// How a floating glass shape comes and goes.
enum GlassArrival {
    /// Fades in with the glass's own materialize transition (the main shape).
    case materialize
    /// Grows out of the nearest shape within the container's spacing, or back into it (the
    /// buttons, the card).
    case morph
}

/// Debug builds can force the pre-macOS 26 material on 26 (`-glassfallback`), to check that look.
enum GlassFallback {
    #if DEBUG
    static var isForced = false
    #else
    static let isForced = false
    #endif
}

extension View {
    /// A floating glass shape: Liquid Glass (regular: text over any background; `interactive`
    /// for buttons: it responds to hover and press) on macOS 26, the popover material before.
    /// Apply after the modifiers that affect the shape's look.
    @ViewBuilder
    func floatingGlass<S: Shape>(_ shape: S, interactive: Bool = false, id: String, in namespace: Namespace.ID,
                                 arrival: GlassArrival) -> some View {
        if #available(macOS 26, *), !GlassFallback.isForced {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .glassEffectID(id, in: namespace)
                .glassEffectTransition(arrival == .materialize ? .materialize : .matchedGeometry)
        } else {
            self.background(VisualEffectMaterial().clipShape(shape))
                .clipShape(shape)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

/// Holds every floating glass shape, so they render together and morph into each other (macOS
/// 26's `GlassEffectContainer`); before, a plain stack.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *), !GlassFallback.isForced {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
