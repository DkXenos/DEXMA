import SwiftUI

/// One battery as a ring, like the Batteries widget: 56 pt, 5 pt line on a white 12 % track,
/// the level in the middle and the name below. White, green while charging (with a bolt), red
/// at 20 % or below; only the track and "—" until it has been read. Dimmed to 45 % when the
/// value is stale (device disconnected: charging is unknown then, so it isn't shown); `age`
/// ("3h ago") when it's older than the others. Level
/// changes spring to the new value (the panel's spring), or jump with Reduce Motion.
struct BatteryGauge: View {
    static let size: CGFloat = 56
    static let lineWidth: CGFloat = 5

    let component: DeviceComponent
    let dimmed: Bool
    let age: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level = component.level
        let charging = component.isCharging == true && level != nil && !dimmed
        let low = level.map { $0 <= DeviceComponent.lowLevel } ?? false
        let color: Color = charging ? DevicesPalette.green : low ? DevicesPalette.red : .white
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(level == nil ? 0 : 1)
                    .animation(reduceMotion ? nil : .spring(Spring(duration: 0.45, bounce: 0.2)), value: level)
                VStack(spacing: 1) {
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DevicesPalette.green)
                    }
                    Text(level.map(String.init) ?? "—")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .opacity(dimmed ? 0.45 : 1)
            VStack(spacing: 1) {
                Text(component.role.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                if let age {
                    Text(age)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}
