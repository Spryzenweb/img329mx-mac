import Foundation
import IOKit
import IOKit.hid

/// IOHIDManager üzerinden farenin üretici (0xFF01) HID arayüzüyle konuşur.
@MainActor
final class HIDTransport {
    nonisolated static let wiredVID = 0xA8A4
    nonisolated static let dongleVID = 0xA8A5
    nonisolated static let productID = 0x2255

    struct Info {
        let vendorID: Int
        let product: String
        var isWireless: Bool { vendorID == HIDTransport.dongleVID }
    }

    var onConnect: ((Info) -> Void)?
    var onDisconnect: (() -> Void)?
    var onNotify: (([UInt8]) -> Void)?
    var onLog: ((String) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var waiter: (id: Int, cmd: UInt8, cont: CheckedContinuation<[UInt8]?, Never>)?
    private var nextWaiterID = 0
    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    var isConnected: Bool { device != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [Self.wiredVID, Self.dongleVID].map {
            [
                kIOHIDVendorIDKey: $0,
                kIOHIDProductIDKey: Self.productID,
                kIOHIDDeviceUsagePageKey: 0xFF01,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.deviceAdded(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.deviceRemoved(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            log(String(format: "IOHIDManagerOpen hata: 0x%08X", r))
        }
    }

    private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func strProp(_ dev: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? ""
    }

    private func deviceAdded(_ dev: IOHIDDevice) {
        let vid = intProp(dev, kIOHIDVendorIDKey)
        let page = intProp(dev, kIOHIDPrimaryUsagePageKey)
        let usage = intProp(dev, kIOHIDPrimaryUsageKey)
        let outSize = intProp(dev, kIOHIDMaxOutputReportSizeKey)
        log(String(format: "Bulundu: VID %04X page %04X usage %04X out %d", vid, page, usage, outSize))
        // Kablolu ve kablosuz aynı anda takılıysa kabloluyu tercih et.
        if let cur = device {
            if intProp(cur, kIOHIDVendorIDKey) == Self.wiredVID || vid != Self.wiredVID { return }
            detach()
        }
        attach(dev)
    }

    private func attach(_ dev: IOHIDDevice) {
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            log(String(format: "IOHIDDeviceOpen hata: 0x%08X", r))
            return
        }
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { me.handleInput(bytes) }
        }, ctx)
        let info = Info(vendorID: intProp(dev, kIOHIDVendorIDKey), product: strProp(dev, kIOHIDProductKey))
        onConnect?(info)
    }

    private func detach() {
        if let w = waiter {
            waiter = nil
            w.cont.resume(returning: nil)
        }
        device = nil
    }

    private func deviceRemoved(_ dev: IOHIDDevice) {
        guard let cur = device, CFEqual(cur, dev) else { return }
        log("Cihaz çıkarıldı")
        detach()
        // Başka eşleşen arayüz varsa ona geç (ör. kablo çıkarılıp alıcı takılıysa).
        if let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
           let next = set.first(where: { !CFEqual($0, dev) }) {
            attach(next)
        } else {
            onDisconnect?()
        }
    }

    private func handleInput(_ bytes: [UInt8]) {
        guard bytes.count >= 2 else { return }
        log("RX " + Packet.hex(bytes))
        if bytes[0] == 0xAA && bytes[1] == 0xFA {
            onNotify?(bytes)
            return
        }
        if let w = waiter, bytes[0] == 0xAA, bytes[1] == w.cmd {
            waiter = nil
            w.cont.resume(returning: bytes)
        }
    }

    private func log(_ s: String) { onLog?(s) }

    private func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { queue.append($0) }
    }

    private func unlock() {
        if queue.isEmpty { busy = false } else { queue.removeFirst().resume() }
    }

    /// Paketi gönderir, AA <cmd> cevabını bekler. Zaman aşımında bir kez tekrar dener.
    func request(_ packet: [UInt8], timeout: Duration = .milliseconds(1000)) async -> [UInt8]? {
        await lock()
        defer { unlock() }
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(100)) }
            if let resp = await exchange(packet, timeout: timeout) { return resp }
            if device == nil { return nil }
        }
        return nil
    }

    private func exchange(_ packet: [UInt8], timeout: Duration) async -> [UInt8]? {
        guard let dev = device else { return nil }
        log("TX " + Packet.hex(packet))
        let r = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else {
            log(String(format: "SetReport hata: 0x%08X", r))
            return nil
        }
        nextWaiterID += 1
        let id = nextWaiterID
        let cmd = packet[1]
        return await withCheckedContinuation { cont in
            waiter = (id, cmd, cont)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if let w = self.waiter, w.id == id {
                    self.waiter = nil
                    self.log("Zaman aşımı (cmd \(String(format: "%02X", cmd)))")
                    w.cont.resume(returning: nil)
                }
            }
        }
    }
}
