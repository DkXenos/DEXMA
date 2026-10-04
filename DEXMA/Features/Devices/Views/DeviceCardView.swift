import SwiftUI

/// One device: icon, name and status ("Connected" with a green dot, or "Last seen 2h ago"),
/// then a ring per battery, evenly spaced. Radius 16, white 6 % fill, 1 px white 7 % stroke,
/// 16 pt padding.
struct DeviceCardView: View {
    let device: Device
    let status: String
    let age: (DeviceComponent) -> String?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(device.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if device.isConnected {
                    Circle()
                        .fill(DevicesPalette.green)
                        .frame(width: 6, height: 6)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(device.displayedComponents, id: \.role) { component in
                    BatteryGauge(component: component, dimmed: !device.isConnected, age: age(component))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(shape.fill(.white.opacity(0.06)))
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1 / max(displayScale, 1)))
    }
}
