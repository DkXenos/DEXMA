import AudioToolbox
import CoreAudio
import Foundation

/// The default output device's volume and mute (CoreAudio). Property listeners keep it current
/// (volume keys, Control Center, AirPods/Buds taking over the output), so nothing polls; they
/// move to the new device when the default output changes.
final class SystemVolume {
    /// 0…1; nil when the output has no volume control (e.g. some HDMI displays).
    private(set) var volume: Float?
    private(set) var isMuted = false
    private(set) var isSettable = false
    var onChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        guard defaultListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.followDefaultDevice() }  // Delivered on the main queue.
        }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, listener) == noErr {
            defaultListener = listener
        }
        followDefaultDevice()
    }

    /// `value` 0…1. Turning it up unmutes, like the volume keys.
    func set(volume value: Float) {
        guard isSettable else { return }
        var level = Float32(min(max(value, 0), 1))
        var address = Self.address(Self.volumeSelector)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        if isMuted, level > 0 {
            var off: UInt32 = 0
            var mute = Self.address(kAudioDevicePropertyMute)
            if AudioObjectHasProperty(device, &mute) {
                AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            }
        }
        read()
    }

    // MARK: Private

    private func followDefaultDevice() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &newDevice) == noErr else { return }
        if newDevice != device {
            removeDeviceListeners()
            device = newDevice
            addDeviceListeners()
        }
        read()
    }

    private func addDeviceListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.read() }  // Delivered on the main queue.
        }
        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            if AudioObjectHasProperty(device, &address) {
                AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
            }
        }
        deviceListener = listener
    }

    private func removeDeviceListeners() {
        guard let deviceListener, device != AudioObjectID(kAudioObjectUnknown) else { return }
        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            if AudioObjectHasProperty(device, &address) {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
            }
        }
        self.deviceListener = nil
    }

    private func read() {
        var address = Self.address(Self.volumeSelector)
        var newVolume: Float?
        var settable = false
        if AudioObjectHasProperty(device, &address) {
            var level: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr { newVolume = level }
            var canSet: DarwinBoolean = false
            settable = AudioObjectIsPropertySettable(device, &address, &canSet) == noErr && canSet.boolValue
        }
        var mute = Self.address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        if AudioObjectHasProperty(device, &mute) {
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted)
        }
        let changed = newVolume != volume || (muted != 0) != isMuted || settable != isSettable
        volume = newVolume
        isMuted = muted != 0
        isSettable = settable
        if changed { onChange?() }
    }
}
