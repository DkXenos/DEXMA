import SwiftUI

/// No device seen yet: a card with the earbuds icon and how to get started (and, if Bluetooth
/// was refused, where to allow it), in the place a device's card would be.
struct DevicesEmptyView: View {
    let bluetoothDenied: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 28, weight: .regular))
            Text("Connect your Galaxy Buds to see their battery here")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
            if bluetoothDenied {
                Text("DEXMA isn't allowed to use Bluetooth. Turn it on in System Settings → Privacy & Security → Bluetooth.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white.opacity(0.45))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(.white.opacity(0.06)))
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1 / max(displayScale, 1)))
    }
}
