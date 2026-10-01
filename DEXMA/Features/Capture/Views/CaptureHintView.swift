import SwiftUI

/// The small pill near the top of the screen in capture mode.
struct CaptureHintView: View {
    var body: some View {
        Text("Draw around anything  ·  Esc to cancel")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .fixedSize()
    }
}
