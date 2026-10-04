import CoreAudio
import Foundation

/// The Bluetooth addresses of the audio devices macOS has right now (a connected headset is one:
/// its UID is "A0-56-2C-6D-3F-40:output"). DEXMA's own `IOBluetoothDevice.isConnected()` says
/// false for a link macOS's audio owns, so at launch this is how already-connected Buds are
/// found. Local: no Bluetooth traffic.
enum BluetoothAudioRoutes {
    /// Normalized (lowercase hex only) addresses.
    static func connectedAddresses() -> Set<String> {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
                                         &devices) == noErr else { return [] }
        var result: Set<String> = []
        for device in devices {
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            address.mSelector = kAudioDevicePropertyTransportType
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &transportSize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            else { continue }
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            address.mSelector = kAudioDevicePropertyDeviceUID
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &uidSize, &uid) == noErr,
                  let text = uid?.takeRetainedValue() as String? else { continue }
            let mac = text.split(separator: ":").first.map(String.init) ?? text
            let normalized = SystemBatteryReader.normalized(mac)
            if normalized.count == 12 { result.insert(normalized) }
        }
        return result
    }
}
