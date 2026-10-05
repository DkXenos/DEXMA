import SwiftUI

/// The floating glass's shapes, in one glass container: the field (a capsule, Spotlight's size and
/// type), the round buttons beside it (they grow out of it as it appears), and the conversation
/// card below (it grows out of the field; claude.ai's page sits in it, see `GlassWebCard`).
/// Regular glass throughout (text over any background), system label colours on it. A click on
/// the window's empty, transparent area hides it, like a click outside.
struct ClaudeGlassView: View {
    let viewModel: ClaudeGlassViewModel
    @Namespace private var glassSpace

    var body: some View {
        let glass = viewModel.glass
        let layout = glass.layout
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.dismiss(returnsFocus: false) }
            GlassGroup(spacing: GlassMetrics.containerSpacing) {
                VStack(alignment: .leading, spacing: GlassMetrics.cardGap) {
                    HStack(alignment: .top, spacing: GlassMetrics.buttonGap) {
                        if glass.isShown {
                            field
                        }
                        if glass.showsAccessories {
                            buttons
                        }
                    }
                    if glass.isShown, viewModel.isExpanded {
                        card(height: layout.card(fieldHeight: viewModel.fieldHeight).height)
                    }
                }
                .scaleEffect(glass.reduceMotion ? 1 : glass.scale, anchor: .top)
            }
            .padding(.leading, layout.field.minX)
            .padding(.top, layout.field.minY)
        }
    }

    // MARK: Field

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: GlassMetrics.fieldHeight / 2, style: .circular)
        let topInset = GlassMetrics.textTopInset
        let bottomInset = GlassMetrics.fieldHeight - GlassTextView.lineHeight - topInset
        return HStack(alignment: .top, spacing: 0) {
            Image(systemName: viewModel.mode.symbol)
                .font(.system(size: GlassMetrics.iconPointSize, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: GlassMetrics.iconBox, height: GlassMetrics.fieldHeight)
                .padding(.leading, GlassMetrics.iconInset)
                .padding(.trailing, GlassMetrics.textInset - GlassMetrics.iconInset - GlassMetrics.iconBox)
            if let image = viewModel.attachment {
                GlassCaptureChip(image: image, remove: viewModel.removeAttachment)
                    .padding(.top, (GlassMetrics.fieldHeight - GlassMetrics.chipSize) / 2)
                    .padding(.trailing, GlassMetrics.chipTextGap)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            GlassInputField(textView: viewModel.textView, height: viewModel.inputHeight)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
            if viewModel.isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: GlassMetrics.fieldHeight)
                    .padding(.leading, 12)
                    .transition(.opacity)
            }
        }
        .padding(.trailing, GlassMetrics.iconInset)
        .frame(width: GlassMetrics.fieldWidth, height: viewModel.fieldHeight, alignment: .topLeading)
        .contentShape(shape)
        .onTapGesture { viewModel.textView.focus() }
        .floatingGlass(shape, id: "field", in: glassSpace, arrival: .materialize)
    }

    // MARK: Buttons

    private var buttons: some View {
        let inset = (GlassMetrics.fieldHeight - GlassMetrics.buttonSize) / 2
        return HStack(spacing: GlassMetrics.buttonGap) {
            GlassCircleButton(symbol: "pencil.and.scribble", label: "Draw to ask Claude",
                              shortcut: viewModel.captureShortcut, id: "capture", namespace: glassSpace,
                              action: viewModel.startCapture)
            GlassCircleButton(symbol: "square.and.pencil", label: "New chat", shortcut: "⌘⇧R",
                              id: "newChat", namespace: glassSpace, action: viewModel.newChat)
            GlassCircleButton(symbol: "arrow.up.right.square", label: "Open in browser", shortcut: "⌘⇧O",
                              id: "browser", namespace: glassSpace, action: viewModel.openInBrowser)
        }
        .padding(.top, inset)
    }

    // MARK: Card

    /// The glass behind claude.ai's page (the page itself is the AppKit `GlassWebCard` above).
    private func card(height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassMetrics.cardRadius, style: .circular)
        return Color.clear
            .frame(width: GlassMetrics.fieldWidth, height: height)
            .contentShape(shape)
            .floatingGlass(shape, id: "card", in: glassSpace, arrival: .morph)
    }
}

/// One of the round buttons right of the field (Spotlight's mode buttons): interactive glass, so
/// it answers hover and press itself.
private struct GlassCircleButton: View {
    let symbol: String
    let label: String
    let shortcut: String
    let id: String
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: GlassMetrics.buttonSymbolSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: GlassMetrics.buttonSize, height: GlassMetrics.buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(Circle(), interactive: true, id: id, in: namespace, arrival: .morph)
        .help(shortcut.isEmpty ? label : "\(label)  \(shortcut)")
        .accessibilityLabel(label)
    }
}

/// A capture waiting for the question: its thumbnail, with a ✕ to drop it while the pointer is on it.
private struct GlassCaptureChip: View {
    let image: CapturedImage
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlassMetrics.chipRadius, style: .continuous)
        Image(decorative: image.thumbnail, scale: 2)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: GlassMetrics.chipSize, height: GlassMetrics.chipSize)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.opacity)
                    .help("Remove the capture")
                    .accessibilityLabel("Remove the capture")
                }
            }
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
            .help("Your capture: sent with the question")
    }
}
