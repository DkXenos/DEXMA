import Foundation
import IOKit
import os

/// The fallback when the Buds' status channel can't be opened: whatever battery level macOS
/// itself knows for the device. First the IORegistry (`BatteryPercent` of a Bluetooth HID
/// service with the device's address: instant, but only HID devices have one), then System
/// Information's Bluetooth report (`system_profiler`, ~1 s: headsets that report their battery
/// over Hands-Free show up there). Runs off the main thread, once per failed attempt; never
/// polled. The result arrives on the main thread.
enum SystemBatteryReader {
    private nonisolated static let logger = Logger(category: "Devices")

    /// `address`: as IOBluetooth gives it ("a0-56-2c-6d-3f-40"); any separator works.
    static func read(address: String, completion: @escaping (BatteryReading?, _ source: String) -> Void) {
        let key = normalized(address)
        DispatchQueue.global(qos: .utility).async {
            let result: (BatteryReading?, String)
            if let level = registryLevel(address: key) {
                result = (BatteryReading(components: [ComponentReading(role: .main, level: level)]), "IORegistry")
            } else if let reading = systemProfilerReading(address: key) {
                result = (reading, "system_profiler")
            } else {
                result = (nil, "none")
            }
            DispatchQueue.main.async { completion(result.0, result.1) }
        }
    }

    /// Lowercase hex digits only, so "A0:56:…" and "a0-56-…" compare equal.
    nonisolated static func normalized(_ address: String) -> String {
        String(address.lowercased().filter(\.isHexDigit))
    }

    private nonisolated static func registryLevel(address: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ name: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let found = property("DeviceAddress") as? String, normalized(found) == address,
                  let percent = property("BatteryPercent") as? Int, (0...100).contains(percent) else { continue }
            return percent
        }
        return nil
    }

    /// The device's entry in `system_profiler -json SPBluetoothDataType`: its
    /// `device_batteryLevelMain` ("80%"), or left/right/case if that's what macOS has.
    private nonisolated static func systemProfilerReading(address: String) -> BatteryReading? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "-detailLevel", "basic", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("system_profiler failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let entry = findDevice(in: json, address: address) else { return nil }
        func level(_ key: String) -> Int? {
            guard let text = entry[key] as? String,
                  let value = Int(text.filter(\.isNumber)), (0...100).contains(value) else { return nil }
            return value
        }
        if let main = level("device_batteryLevelMain") {
            return BatteryReading(components: [ComponentReading(role: .main, level: main)])
        }
        let parts = [(ComponentRole.left, "device_batteryLevelLeft"), (.right, "device_batteryLevelRight"),
                     (.case, "device_batteryLevelCase")]
            .map { ComponentReading(role: $0.0, level: level($0.1)) }
        let reading = BatteryReading(components: parts)
        return reading.hasLevel ? reading : nil
    }

    private nonisolated static func findDevice(in json: Any, address: String) -> [String: Any]? {
        if let dictionary = json as? [String: Any] {
            if let found = dictionary["device_address"] as? String, normalized(found) == address {
                return dictionary
            }
            for value in dictionary.values {
                if let match = findDevice(in: value, address: address) { return match }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let match = findDevice(in: value, address: address) { return match }
            }
        }
        return nil
    }
}
