import Foundation
import IOBluetooth
import os

/// One connected pair of Galaxy Buds: finds the model's status service in the SDP records
/// (cached ones first, a query otherwise; channel numbers are never hard-coded), opens an RFCOMM
/// channel to it and turns the status messages the Buds send into readings.
///
/// Read-only: nothing is ever written to the channel. The Buds send EXTENDED_STATUS_UPDATED by
/// themselves as soon as the channel opens, and STATUS_UPDATED on every change, so no request is
/// needed. If the channel can't be opened (another app holds it, an unsupported model, no
/// permission) the level macOS itself knows is read instead (`SystemBatteryReader`), and opening
/// is retried after 2 s, 10 s and 60 s, then not again until the next connect. Everything runs
/// on the main thread's run loop, driven by IOBluetooth's callbacks: nothing polls.
final class BudsConnection: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private static let logger = Logger(category: "Buds")
    static let retryDelays: [TimeInterval] = [2, 10, 60]
    private static let sdpTimeout: TimeInterval = 10
    private static let openTimeout: TimeInterval = 10
    /// The channel is open but nothing came: show macOS's level meanwhile.
    private static let firstStatusTimeout: TimeInterval = 5
    private static let attachTimeout: TimeInterval = 10

    let device: IOBluetoothDevice
    let id: String
    private(set) var model: BudsModel?

    /// The device is Galaxy Buds (`model`): from its cached records right away, or after the query.
    var onIdentified: ((BudsModel) -> Void)?
    /// Its services show it isn't Galaxy Buds.
    var onNotBuds: (() -> Void)?
    var onReading: ((BatteryReading) -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder: BudsFrameDecoder?
    private var attempt = 0
    private var timeout: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var stopped = false
    private var sdpPending = false
    /// A status message from the Buds arrived (the fallback is no longer needed).
    private var hasStatus = false
    /// This process has its own handle on the Buds' link (see `connect`).
    private var attached = false
    private var attachPending = false
    private var bytesReceived = 0

    /// `model`: already known from the name or cached records (nil: the query decides).
    init(device: IOBluetoothDevice, id: String, model: BudsModel?) {
        self.device = device
        self.id = id
        self.model = model
        super.init()
    }

    func start() {
        if let model { onIdentified?(model) }
        connect(usingCache: true)
    }

    /// Disconnected or forgotten: close the channel and stop everything.
    func stop() {
        stopped = true
        timeout?.cancel()
        retry?.cancel()
        closeChannel()
    }

    // MARK: Steps

    private func connect(usingCache: Bool) {
        guard !stopped else { return }
        // The Buds' link belongs to macOS (audio): this process's device object says "not
        // connected" until it attaches to it. Only ever done after the connect notification,
        // so it joins the existing link (it never calls the Buds up).
        guard attached || device.isConnected() else {
            attach(thenUsingCache: usingCache)
            return
        }
        if usingCache, let model, let channelID = SDPRecords.rfcommChannel(of: device, service: model.serviceUUID) {
            open(channelID)
        } else {
            querySDP()
        }
    }

    private func attach(thenUsingCache usingCache: Bool) {
        guard !attachPending else { return }
        attachPending = true
        Self.logger.notice("Attaching to the Buds' connection")
        let status = device.openConnection(self)
        guard status == kIOReturnSuccess else {
            attachPending = false
            fail("Couldn't attach to the Buds' connection (\(Self.describe(status)))")
            return
        }
        arm(Self.attachTimeout) { [weak self] in
            guard let self, self.attachPending else { return }
            self.attachPending = false
            self.fail("Attaching to the Buds' connection timed out")
        }
        pendingUsesCache = usingCache
    }

    private var pendingUsesCache = true

    private func attachCompleted(status: IOReturn) {
        guard attachPending, !stopped else { return }
        attachPending = false
        timeout?.cancel()
        // "Connection exists" comes back as an error too: carry on either way; opening the
        // channel is what decides.
        attached = true
        Self.logger.notice("Attached (\(Self.describe(status), privacy: .public)); connected \(self.device.isConnected())")
        connect(usingCache: pendingUsesCache)
    }

    /// All services (a query for specific UUIDs silently returns nothing since macOS 13).
    private func querySDP() {
        Self.logger.notice("Querying the device's services (SDP)")
        sdpPending = true
        let status = device.performSDPQuery(self)
        guard status == kIOReturnSuccess else {
            sdpPending = false
            fail("SDP query didn't start (\(Self.describe(status)))")
            return
        }
        arm(Self.sdpTimeout) { [weak self] in
            guard let self, self.sdpPending else { return }
            self.sdpPending = false
            self.fail("SDP query timed out")
        }
    }

    private func sdpCompleted(status: IOReturn) {
        guard sdpPending, !stopped else { return }
        sdpPending = false
        timeout?.cancel()
        let name = device.name ?? ""
        let uuids = SDPRecords.serviceUUIDs(of: device)
        Self.logger.notice("SDP for \(name, privacy: .public): \(Self.describe(status), privacy: .public), services \(uuids.joined(separator: " "), privacy: .public)")
        let namedModel = BudsIdentification.model(named: name)
        guard let identified = BudsIdentification.model(name: name, serviceUUIDs: uuids) else {
            if namedModel != nil {
                giveUp("named like Galaxy Buds but has none of their status services (unsupported model)")
            } else {
                onNotBuds?()
                stop()
            }
            return
        }
        if model != identified {
            let wasKnown = model != nil
            model = identified
            if !wasKnown { onIdentified?(identified) }
        }
        guard let channelID = SDPRecords.rfcommChannel(of: device, service: identified.serviceUUID) else {
            giveUp("no RFCOMM channel for \(identified.displayName)'s status service")
            return
        }
        open(channelID)
    }

    private func open(_ channelID: BluetoothRFCOMMChannelID) {
        guard let model, !stopped else { return }
        decoder = BudsFrameDecoder(framing: model.framing)
        var newChannel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess, let newChannel else {
            fail("RFCOMM channel \(channelID) didn't open (\(Self.describe(status)))")
            return
        }
        channel = newChannel
        Self.logger.notice("Opening RFCOMM channel \(channelID) for \(model.displayName, privacy: .public)")
        arm(Self.openTimeout) { [weak self] in
            guard let self, let channel = self.channel, !channel.isOpen() else { return }
            self.fail("RFCOMM channel \(channelID) timed out opening")
        }
    }

    private func opened(_ status: IOReturn) {
        guard let channel, !stopped else { return }
        // The status is sometimes an error although the channel did open (a known macOS quirk).
        guard status == kIOReturnSuccess || channel.isOpen() else {
            fail("RFCOMM channel didn't open (\(Self.describe(status)))")
            return
        }
        timeout?.cancel()
        Self.logger.notice("RFCOMM channel open (\(Self.describe(status), privacy: .public)); waiting for the Buds' status")
        arm(Self.firstStatusTimeout) { [weak self] in
            guard let self, !self.hasStatus else { return }
            Self.logger.notice("No status yet: showing macOS's own level meanwhile")
            self.readFallback()
        }
    }

    private func received(_ bytes: [UInt8]) {
        guard !stopped, let model, decoder != nil else { return }
        let rejectedBefore = decoder?.rejected ?? 0
        let messages = decoder?.feed(bytes) ?? []
        if let rejected = decoder?.rejected, rejected > rejectedBefore {
            Self.logger.notice("Ignored malformed data (\(rejected) bad frames so far)")
        }
        // The first bytes and messages, for diagnosing a model whose stream looks different.
        if bytesReceived < 256 {
            let hex = bytes.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
            Self.logger.notice("Received \(bytes.count) bytes: \(hex, privacy: .public); messages \(messages.map { String(format: "0x%02x/%d", $0.id, $0.payload.count) }.joined(separator: " "), privacy: .public)")
        }
        bytesReceived += bytes.count
        for message in messages {
            guard let reading = BudsStatusParser.reading(from: message, model: model) else { continue }
            if !hasStatus {
                Self.logger.notice("First battery reading: \(reading.components.map { "\($0.role.shortTitle) \($0.level.map(String.init) ?? "?")" }.joined(separator: ", "), privacy: .public)")
                hasStatus = true
                attempt = 0
                timeout?.cancel()
            }
            onReading?(reading)
        }
    }

    private func closed() {
        channel = nil
        guard !stopped else { return }
        // If the Buds disconnected, the monitor's notification stops this before the retry.
        fail("RFCOMM channel closed by the device")
    }

    // MARK: Failure

    /// Shows macOS's level and tries again later (2 s, 10 s, 60 s), then gives up until the next
    /// connect.
    private func fail(_ reason: String) {
        guard !stopped else { return }
        timeout?.cancel()
        closeChannel()
        readFallback()
        guard attempt < Self.retryDelays.count else {
            Self.logger.notice("\(reason, privacy: .public); giving up until the next connect")
            return
        }
        let delay = Self.retryDelays[attempt]
        attempt += 1
        Self.logger.notice("\(reason, privacy: .public); retrying in \(Int(delay)) s")
        let work = DispatchWorkItem { [weak self] in self?.connect(usingCache: false) }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Nothing to retry (the model can't be read): macOS's level only.
    private func giveUp(_ reason: String) {
        Self.logger.notice("\(reason, privacy: .public): showing macOS's own level")
        closeChannel()
        readFallback()
    }

    private func readFallback() {
        guard !hasStatus, let address = device.addressString else { return }
        SystemBatteryReader.read(address: address) { [weak self] reading, source in
            guard let self, !self.stopped, !self.hasStatus else { return }
            guard let reading else {
                Self.logger.notice("macOS knows no battery level for this device either")
                return
            }
            Self.logger.notice("Fallback level from \(source, privacy: .public)")
            self.onReading?(reading)
        }
    }

    private func closeChannel() {
        guard let channel else { return }
        self.channel = nil
        channel.setDelegate(nil)
        _ = channel.close()
    }

    private func arm(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        timeout?.cancel()
        let work = DispatchWorkItem(block: action)
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func describe(_ status: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: status))
    }

    // MARK: IOBluetooth callbacks (the main run loop; hopped onto the main actor)

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in self?.attachCompleted(status: status) }
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in self?.sdpCompleted(status: status) }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!,
                                       length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        // Only valid during this call: copy it.
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        DispatchQueue.main.async { [weak self] in self?.received(bytes) }
    }

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        DispatchQueue.main.async { [weak self] in self?.opened(error) }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async { [weak self] in self?.closed() }
    }
}
