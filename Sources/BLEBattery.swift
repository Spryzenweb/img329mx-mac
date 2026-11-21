import CoreBluetooth
import Foundation

/// Fare Bluetooth'tayken pil seviyesini standart BLE pil servisinden (180F / 2A19) okur.
/// Yalnızca okur ve bildirime abone olur; fareye hiçbir şey yazmaz.
/// (Faredeki diğer özel servis Freqchip'in yazılım güncelleme servisidir, ona dokunulmaz.)
final class BLEBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onBattery: (@MainActor (Int?) -> Void)?

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var level: CBCharacteristic?
    private var wanted = false
    private var pollTimer: Timer?

    func start() {
        wanted = true
        if let central {
            if central.state == .poweredOn { attach(central) }
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        pollTimer?.invalidate()
        // Bildirim gelmezse diye 2 dakikada bir yeniden oku
        pollTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        wanted = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        level = nil
        publish(nil)
    }

    private func poll() {
        guard wanted, let central, central.state == .poweredOn else { return }
        if let p = peripheral, let level, p.state == .connected {
            p.readValue(for: level)
        } else {
            attach(central)
        }
    }

    private func publish(_ v: Int?) {
        guard let cb = onBattery else { return }
        MainActor.assumeIsolated { cb(v) }
    }

    private func attach(_ c: CBCentralManager) {
        let list = c.retrieveConnectedPeripherals(withServices: [Self.batteryService, CBUUID(string: "1812")])
        guard let p = list.first(where: { ($0.name ?? "").uppercased().contains("329MX") }) else { return }
        if peripheral?.identifier == p.identifier, p.state == .connected, level != nil { return }
        peripheral = p
        p.delegate = self
        c.connect(p)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn, wanted { attach(c) }
        if c.state != .poweredOn { publish(nil) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.batteryService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if p.identifier == peripheral?.identifier {
            level = nil
            publish(nil)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        p.discoverCharacteristics([Self.batteryLevel], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
        level = ch
        p.readValue(for: ch)
        if ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.batteryLevel, let v = ch.value?.first else { return }
        publish(min(Int(v), 100))
    }
}
