import Foundation
import Testing
@testable import DEXMA

struct DeviceModelTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func reading(_ left: Int?, _ right: Int?, _ caseLevel: Int?, charging: Bool? = nil) -> BatteryReading {
        BatteryReading(components: [ComponentReading(role: .left, level: left, isCharging: charging),
                                    ComponentReading(role: .right, level: right, isCharging: charging),
                                    ComponentReading(role: .case, level: caseLevel, isCharging: nil)])
    }

    @Test func unknownValuesKeepTheirPreviousValueAndTime() {
        var device = Device(id: "a", name: "Mewo", kind: .buds, source: .bluetoothBuds, lastSeen: start)
        #expect(device.components.map(\.role) == [.left, .right, .case] && device.components.allSatisfy { !$0.isKnown })
        device.apply(reading(80, 75, 40), at: start)
        let later = start.addingTimeInterval(3 * 3600)
        let changed = device.apply(reading(70, 68, nil), at: later)
        #expect(changed)
        #expect(device.component(.case)?.level == 40 && device.component(.case)?.updatedAt == start)
        #expect(device.component(.left)?.updatedAt == later && device.lastSeen == later)
        #expect(device.isStale(device.component(.case)!) && !device.isStale(device.component(.left)!))
        // A reading of only unknowns changes nothing.
        let unchanged = device.apply(reading(nil, nil, nil), at: later.addingTimeInterval(60))
        #expect(!unchanged)
    }

    @Test func aNewerSingleValueShowsAlone() {
        var device = Device(id: "a", name: "Mewo", kind: .buds, source: .bluetoothBuds, lastSeen: start)
        device.apply(reading(80, 75, 40), at: start)
        device.apply(BatteryReading(components: [ComponentReading(role: .main, level: 77)]), at: start.addingTimeInterval(60))
        #expect(device.displayedComponents.map(\.role) == [.main])
        device.apply(reading(79, nil, nil), at: start.addingTimeInterval(120))
        #expect(device.displayedComponents.map(\.role) == [.left, .right, .case])
    }

    @Test func lowAndChargingColours() {
        #expect(DeviceComponent(role: .left, level: 20, isCharging: false).isLow)
        #expect(!DeviceComponent(role: .left, level: 21).isLow)
        #expect(!DeviceComponent(role: .left, level: 5, isCharging: true).isLow)
        #expect(!DeviceComponent(role: .left).isLow)
    }

    @Test func relativeTimesAndWhenTheyChange() {
        func text(_ seconds: TimeInterval) -> String { RelativeTime.text(since: start, now: start.addingTimeInterval(seconds)) }
        #expect(text(5) == "just now" && text(60) == "1m ago" && text(3599) == "59m ago")
        #expect(text(2 * 3600 + 5) == "2h ago" && text(3 * 86400) == "3d ago")
        #expect(RelativeTime.nextChange(since: start, now: start.addingTimeInterval(10)) == start.addingTimeInterval(60))
        #expect(RelativeTime.nextChange(since: start, now: start.addingTimeInterval(130)) == start.addingTimeInterval(180))
        #expect(RelativeTime.nextChange(since: start, now: start.addingTimeInterval(7300)) == start.addingTimeInterval(3 * 3600))
    }

    @Test func lowBatteryAlertsOnceAt20AndAgainAt10() {
        var policy = LowBatteryPolicy()
        func observe(_ reading: BatteryReading, first: Bool = false) -> Int? {
            policy.observe(reading, isFirstReading: first)
        }
        #expect(observe(reading(60, 70, 50), first: true) == nil)
        #expect(observe(reading(21, 70, 50)) == nil)
        #expect(observe(reading(20, 70, 50)) == 20)
        #expect(observe(reading(19, 70, 50)) == nil)
        #expect(observe(reading(10, 70, 50)) == 10)
        #expect(observe(reading(5, 70, 5)) == nil)  // The case never alerts.
        // Charged back up past 25: armed again.
        #expect(observe(reading(30, 70, 50)) == nil)
        #expect(observe(reading(18, 70, 50)) == 20)
        // Already low when it connects: the connect peek covers it; charging never alerts.
        policy = LowBatteryPolicy()
        #expect(observe(reading(15, 70, 50), first: true) == nil)
        #expect(observe(reading(14, 70, 50)) == nil)
        #expect(observe(reading(9, 70, 50, charging: true)) == nil)
    }

    @Test func summariesLeaveUnknownsOut() {
        var device = Device(id: "a", name: "Mewo", kind: .buds, source: .bluetoothBuds, lastSeen: start)
        #expect(DeviceSummary.band(device) == "Mewo")
        device.apply(reading(80, 18, nil), at: start)
        #expect(DeviceSummary.band(device) == "Mewo  L 80%  R 18%")
        let activity = DeviceSummary.activity(device, isAlert: true)
        #expect(activity.text == "L 80% · R 18%" && activity.parts.map(\.isLow) == [false, true])
        #expect(activity.symbol == "earbuds" && activity.isAlert)
        device.apply(reading(80, 18, 40), at: start)
        let withCase = DeviceSummary.activity(device, isAlert: false)
        #expect(withCase.mainText == "L 80% · R 18%" && withCase.casePart?.text == "Case 40%")
    }
}
