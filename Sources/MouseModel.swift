import Foundation
import IOKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, keys, dpi, macros, lighting, settings, log
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .keys: return "Mouse Tuşları"
        case .dpi: return "Mouse DPI"
        case .macros: return "Makrolar"
        case .lighting: return "Işıklandırma"
        case .settings: return "Ayarlar"
        case .log: return "Günlük"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .keys: return "computermouse"
        case .dpi: return "gauge.with.dots.needle.67percent"
        case .macros: return "record.circle"
        case .lighting: return "lightbulb"
        case .settings: return "slider.horizontal.3"
        case .log: return "list.bullet.rectangle"
        }
    }
}

@MainActor
final class MouseModel: ObservableObject {
    @Published var page: Page = .home

    @Published var connected = false
    @Published var isWireless = false
    @Published var productName = ""
    @Published var firmware: String?
    @Published var battery: Int?
    @Published var charging = false

    /// Ekranda düzenlenen ayarlar
    @Published var config = MouseConfig()
    /// Cihazdan son okunan ayarlar
    @Published private(set) var deviceConfig = MouseConfig()
    @Published var keys: [KeyBinding] = KeyMap.defaults
    @Published private(set) var deviceKeys: [KeyBinding] = KeyMap.defaults
    @Published private(set) var keysLoaded = false
    @Published private(set) var loaded = false

    @Published var library = MacroLibrary.load() {
        didSet { if !demo { library.save() } }
    }

    /// Fare Bluetooth ile bağlı mı (BLE'de ayar arayüzü yok, sadece bilgi amaçlı)
    @Published var bluetoothConnected = false
    /// Bluetooth'tayken BLE pil servisinden okunan pil seviyesi
    @Published var btBattery: Int?
    @Published var batteryUpdated: Date?

    @Published var busy = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var logLines: [String] = []

    /// Windows yazılımı varsayılan olarak 1. profili (0) kullanır.
    let profile: UInt8 = 0
    let demo = CommandLine.arguments.contains("--demo")

    var configDirty: Bool { loaded && config != deviceConfig }
    var keysDirty: Bool { keysLoaded && keys != deviceKeys }
    var macrosDirty: Bool { library.pendingUpload }
    var dirty: Bool { configDirty || keysDirty || macrosDirty }

    private let hid = HIDTransport()
    private let ble = BLEBattery()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init() {
        hid.onLog = { [weak self] in self?.appendLog($0) }
        hid.onConnect = { [weak self] info in
            guard let self else { return }
            self.connected = true
            self.isWireless = info.isWireless
            self.productName = info.product
            Task { await self.refresh() }
        }
        hid.onDisconnect = { [weak self] in
            guard let self else { return }
            self.connected = false
            self.loaded = false
            self.keysLoaded = false
            self.firmware = nil
            self.battery = nil
            self.setStatus("Lütfen cihaz bağlayın", error: false)
        }
        hid.onNotify = { [weak self] in self?.handleNotify($0) }
        setStatus("Lütfen cihaz bağlayın", error: false)

        ble.onBattery = { [weak self] v in
            self?.btBattery = v
            if v != nil { self?.batteryUpdated = Date() }
        }
        checkBluetooth()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkBluetooth() }
        }
        // Kablolu / 2.4 GHz'de pili ara ara tazele (menü çubuğu için)
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor in await self.refreshBattery() }
            }
        }

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--page"), i + 1 < args.count, let p = Page(rawValue: args[i + 1]) {
            page = p
        }
        if demo { loadDemo() }
    }

    /// Arayüzü cihaz olmadan görmek için: IMG-329MX --demo [--page keys]
    private func loadDemo() {
        var r = [UInt8](repeating: 0, count: 64)
        r[0] = 0xAA; r[1] = 0x0E; r[4] = 0x2E
        r[9] = 3; r[10] = 4; r[11] = 6; r[12] = 2
        var cfg = MouseConfig(response: r)!
        for (i, d) in [800, 1200, 1600, 3200, 6400, 12000].enumerated() { cfg.setDpi(i, d) }
        cfg.liftOff = 1; cfg.debounce = 10; cfg.sleepMinutes = 255; cfg.eSports = true; cfg.angleSnap = true
        connected = true; isWireless = false; firmware = "2.1.4"; battery = 100; charging = true
        deviceConfig = cfg; config = cfg; loaded = true
        var k = KeyMap.defaults
        k[4] = .macro(0, count: 1, mode: 0)
        deviceKeys = k; keys = k; keysLoaded = true
        if library.macros.isEmpty {
            library.macros = [
                Macro(name: "Kopyala-yapıştır", events: [
                    .init(kind: .keyDown, code: 0xE3, delay: 20), .init(kind: .keyDown, code: 0x06, delay: 40),
                    .init(kind: .keyUp, code: 0x06, delay: 20), .init(kind: .keyUp, code: 0xE3, delay: 80),
                    .init(kind: .keyDown, code: 0xE3, delay: 20), .init(kind: .keyDown, code: 0x19, delay: 40),
                    .init(kind: .keyUp, code: 0x19, delay: 20), .init(kind: .keyUp, code: 0xE3, delay: 10),
                ]),
                Macro(name: "Hızlı tık", events: [
                    .init(kind: .mouseDown, code: 0x01, delay: 15), .init(kind: .mouseUp, code: 0x01, delay: 15),
                    .init(kind: .mouseDown, code: 0x01, delay: 15), .init(kind: .mouseUp, code: 0x01, delay: 15),
                ]),
            ]
            library.pendingUpload = false
        }
        setStatus("Demo modu (cihaz yok)", error: false)
    }

    /// Bluetooth'ta fare VID 2717 / PID 32B0 olarak görünür. IORegistry'den okunur;
    /// cihaz açılmadığı için Giriş İzleme izni gerekmez.
    private func checkBluetooth() {
        let match = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
        match["VendorID"] = 0x2717
        match["ProductID"] = 0x32B0
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var found = false
        while case let s = IOIteratorNext(iter), s != 0 {
            let transport = IORegistryEntryCreateCFProperty(s, "Transport" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String ?? ""
            if transport.localizedCaseInsensitiveContains("bluetooth") { found = true }
            IOObjectRelease(s)
        }
        if found != bluetoothConnected {
            bluetoothConnected = found
            if found { ble.start() } else { ble.stop() }
        }
    }

    /// Menü çubuğunda gösterilecek pil: USB/2.4 GHz'de HID'den, Bluetooth'ta BLE'den
    var trayBattery: Int? { connected ? battery : (bluetoothConnected ? btBattery : nil) }
    var trayCharging: Bool { connected && charging }
    var trayMode: String {
        if connected { return isWireless ? "2.4 GHz alıcı" : "USB kablo" }
        return bluetoothConnected ? "Bluetooth" : "Bağlı değil"
    }

    func refreshBattery() async {
        guard connected, loaded, !busy, !demo else { return }
        if let b = await hid.request(Packet.battery(profile: profile)) {
            battery = min(Int(b[8]), 100)
            charging = b[9] != 0
            batteryUpdated = Date()
        }
    }

    private func appendLog(_ s: String) {
        logLines.append("\(Self.timeFmt.string(from: Date()))  \(s)")
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
    }

    func setStatus(_ s: String, error: Bool) {
        status = s
        statusIsError = error
    }

    // MARK: - Okuma

    func refresh() async {
        guard connected, !busy, !demo else { return }
        busy = true
        defer { busy = false }
        setStatus("Okunuyor…", error: false)

        if let v = await hid.request(Packet.version()) {
            firmware = Self.parseVersion(v)
        }
        if let b = await hid.request(Packet.battery(profile: profile)) {
            battery = min(Int(b[8]), 100)
            charging = b[9] != 0
            batteryUpdated = Date()
        }
        guard let resp = await hid.request(Packet.readConfig(profile: profile)),
              let cfg = MouseConfig(response: resp) else {
            setStatus(isWireless
                      ? "Fare cevap vermedi. Fareyi uyandırmak için hareket ettirip Yenile'ye basın."
                      : "Fare cevap vermedi.", error: true)
            return
        }
        deviceConfig = cfg
        config = cfg
        loaded = true

        if let kr = await hid.request(Packet.readKeys(profile: profile)), let k = KeyMap.parse(kr) {
            deviceKeys = k
            keys = k
            keysLoaded = true
            setStatus("Ayarlar okundu", error: false)
        } else {
            setStatus("Ayarlar okundu, tuş atamaları okunamadı", error: true)
        }
    }

    // MARK: - Kaydetme

    func save() async {
        guard connected, loaded, !busy else { return }
        if demo {
            deviceConfig = config
            deviceKeys = keys
            library.pendingUpload = false
            setStatus("Demo: kaydedildi (cihaza bir şey gönderilmedi)", error: false)
            return
        }
        busy = true
        defer { busy = false }
        setStatus("Kaydediliyor…", error: false)
        var problems: [String] = []

        if macrosDirty {
            if await uploadMacros() {
                library.pendingUpload = false
                library.everUploaded = true
            } else {
                problems.append("makrolar")
            }
        }

        if keysDirty {
            let k = keys
            if await hid.request(Packet.writeKeys(profile: profile, entries: k.map(\.b))) != nil {
                try? await Task.sleep(for: .milliseconds(100))
                if let kr = await hid.request(Packet.readKeys(profile: profile)), let back = KeyMap.parse(kr) {
                    deviceKeys = back
                    if back != k { problems.append("tuş atamaları farklı okundu") }
                } else {
                    deviceKeys = k
                }
            } else {
                problems.append("tuş atamaları")
            }
        }

        if configDirty {
            problems += await saveConfig()
        }

        if problems.isEmpty {
            setStatus("Mouse başarıyla kaydedildi!", error: false)
        } else {
            setStatus("Kaydedilemedi: " + problems.joined(separator: ", "), error: true)
        }
    }

    private func saveConfig() async -> [String] {
        let c = config
        let old = deviceConfig
        guard await hid.request(c.writePacket(profile: profile)) != nil else { return ["ayarlar"] }
        // Windows yazılımı bu üç ayarı ayrıca kendi komutlarıyla da gönderiyor.
        if c.lightMode != old.lightMode {
            _ = await hid.request(Packet.lighting(profile: profile, mode: UInt8(c.lightMode)))
        }
        if c.reportRate != old.reportRate {
            _ = await hid.request(Packet.reportRate(profile: profile, rate: UInt8(c.reportRate)))
        }
        if c.activeStage != old.activeStage || c.dpi(c.activeStage) != old.dpi(old.activeStage) {
            _ = await hid.request(Packet.dpiStage(profile: profile,
                                                  stage: UInt8(c.activeStage + 1),
                                                  dpi: c.dpi(c.activeStage)))
        }

        try? await Task.sleep(for: .milliseconds(150))
        guard let resp = await hid.request(Packet.readConfig(profile: profile)),
              let back = MouseConfig(response: resp) else {
            deviceConfig = c
            return []
        }
        deviceConfig = back
        let mismatch = Self.diff(expected: c, actual: back)
        if mismatch.isEmpty {
            config = back
            return []
        }
        return ["cihaz farklı okudu (" + mismatch.joined(separator: ", ") + ")"]
    }

    private func uploadMacros() async -> Bool {
        for p in MacroCodec.packets(library.macros) {
            guard await hid.request(p) != nil else { return false }
        }
        return true
    }

    func revert() {
        config = deviceConfig
        keys = deviceKeys
    }

    private static func diff(expected e: MouseConfig, actual a: MouseConfig) -> [String] {
        var out: [String] = []
        if e.lightMode != a.lightMode { out.append("ışık") }
        if e.reportRate != a.reportRate { out.append("algılama hızı") }
        if e.activeStage != a.activeStage { out.append("aktif DPI") }
        for i in 0..<MouseConfig.stages where e.dpi(i) != a.dpi(i) { out.append("DPI \(i + 1)") }
        if e.scrollDirection != a.scrollDirection { out.append("scroll yönü") }
        if e.liftOff != a.liftOff { out.append("LOD") }
        if e.sensorBits != a.sensorBits { out.append("sensör") }
        if e.debounce != a.debounce { out.append("tuş gecikmesi") }
        if e.sleepMinutes != a.sleepMinutes { out.append("bekleme süresi") }
        if e.eSportsRaw != a.eSportsRaw { out.append("e-spor") }
        return out
    }

    private static func parseVersion(_ r: [UInt8]) -> String? {
        guard r.count >= 26 else { return nil }
        let digits = r[23...25].map { (0x30...0x39).contains($0) ? Character(UnicodeScalar($0)) : "0" }
        return "\(digits[0]).\(digits[1]).\(digits[2])"
    }

    /// AA FA ... bildirimleri (fare üzerindeki tuşlar, pil)
    private func handleNotify(_ b: [UInt8]) {
        guard b.count >= 11 else { return }
        if b[2] == 0x38 && b[3] == 0x38 { return }
        if b[9] == 0xFF || b[10] == 0xFF { return }
        switch b[8] {
        case 0x10:
            let stage = max(Int(b[9]), 1) - 1
            if stage < MouseConfig.stages {
                config.activeStage = stage
                deviceConfig.activeStage = stage
            }
            if (1...4).contains(Int(b[10])) {
                config.reportRate = Int(b[10])
                deviceConfig.reportRate = Int(b[10])
            }
        case 0x11:
            let mode = min(Int(b[9]), Lighting.modes.count - 1)
            config.lightMode = mode
            deviceConfig.lightMode = mode
        case 0xD0:
            battery = min(Int(b[9]), 100)
            charging = b[10] != 0
            batteryUpdated = Date()
        default:
            break
        }
    }

    // MARK: - Makro düzenleme

    func editMacros(_ f: (inout [Macro]) -> Void) {
        var m = library.macros
        f(&m)
        guard m != library.macros else { return }
        var lib = library
        lib.macros = m
        lib.pendingUpload = true
        library = lib
    }

    func dpiBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { self.config.dpi(i) }, set: { self.config.setDpi(i, $0) })
    }
}

enum Lighting {
    struct Mode: Identifiable {
        let id: Int
        let name: String
        let color: Color?
    }

    /// Bu modelin ışık seçenekleri (DeviceDriver.exe combobox @ 0x42e336)
    static let modes: [Mode] = [
        .init(id: 0, name: "Kapalı", color: nil),
        .init(id: 1, name: "Kırmızı", color: Color(red: 1, green: 0.18, blue: 0.2)),
        .init(id: 2, name: "Yeşil", color: Color(red: 0.2, green: 0.85, blue: 0.35)),
        .init(id: 3, name: "Mavi", color: Color(red: 0.15, green: 0.4, blue: 1)),
        .init(id: 4, name: "Camgöbeği", color: Color(red: 0.1, green: 0.85, blue: 0.95)),
        .init(id: 5, name: "Sarı", color: Color(red: 1, green: 0.85, blue: 0.1)),
        .init(id: 6, name: "Mor", color: Color(red: 0.7, green: 0.3, blue: 1)),
        .init(id: 7, name: "Beyaz", color: .white),
        .init(id: 8, name: "Renk döngüsü", color: nil),
        .init(id: 9, name: "Nefes döngüsü", color: nil),
    ]

    static func name(_ m: Int) -> String {
        modes.first(where: { $0.id == m })?.name ?? "Bilinmiyor (\(m))"
    }
}
