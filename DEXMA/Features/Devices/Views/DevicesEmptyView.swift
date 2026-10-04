import SwiftUI

/// No device seen yet: a centred earbuds icon and how to get started (and, if Bluetooth was
/// refused, where to allow it).
struct DevicesEmptyView: View {
    let bluetoothDenied: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 28, weight: .regular))
            Text("Connect your Galaxy Buds to see their battery here")
                .font(.system(size: 13))
            if bluetoothDenied {
                Text("DEXMA isn't allowed to use Bluetooth. Turn it on in System Settings → Privacy & Security → Bluetooth.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
