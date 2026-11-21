import Foundation

/// IMG-329MX (YJX-CHIP, VID A8A4 kablolu / A8A5 2.4G alıcı, PID 2255) HID protokolü.
/// Windows yazılımı (DeviceDriver.exe 1.2.2) disassemble edilerek çıkarıldı; ayrıntılar PROTOCOL.md'de.
///
/// Her paket 64 bayt, report ID 0, arayüz 2 (usage page 0xFF01).
///   istek : 55 <cmd> <b2> <checksum> <veri 4..63>
///   cevap : AA <cmd> ...
///   checksum = (bayt 4..63 toplamı) & 0xFF
enum Cmd: UInt8 {
    case version = 0x03
    case readKeys = 0x08
    case writeKeys = 0x09
    case macroData = 0x0D
    case readConfig = 0x0E
    case writeConfig = 0x0F
    case macroCommit = 0x10
    case lighting = 0x21
    case dpiStage = 0x22
    case reportRate = 0x23
    case battery = 0x30
}

enum Packet {
    static func checksum(_ p: [UInt8]) -> UInt8 {
        var sum = 0
        for i in 4..<64 { sum += Int(p[i]) }
        return UInt8(truncatingIfNeeded: sum)
    }

    static func make(_ cmd: Cmd, _ b2: UInt8, _ fill: (inout [UInt8]) -> Void = { _ in }) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 64)
        p[0] = 0x55
        p[1] = cmd.rawValue
        p[2] = b2
        fill(&p)
        p[3] = checksum(p)
        return p
    }

    static func version() -> [UInt8] { make(.version, 0x00) }

    static func battery(profile: UInt8) -> [UInt8] {
        make(.battery, 0xA5) { p in p[4] = 0x2E; p[7] = profile }
    }

    static func readConfig(profile: UInt8) -> [UInt8] {
        make(.readConfig, 0xA5) { p in p[4] = 0x2E; p[7] = profile }
    }

    static func readKeys(profile: UInt8) -> [UInt8] {
        make(.readKeys, 0xA5) { p in p[4] = 0x20; p[7] = profile }
    }

    static func writeKeys(profile: UInt8, entries: [[UInt8]]) -> [UInt8] {
        make(.writeKeys, 0xA5) { p in
            p[4] = 0x20; p[7] = profile
            for (i, e) in entries.prefix(KeyMap.slots).enumerated() {
                for j in 0..<4 { p[8 + i * 4 + j] = e[j] }
            }
        }
    }

    static func lighting(profile: UInt8, mode: UInt8) -> [UInt8] {
        make(.lighting, 0xA5) { p in p[4] = 0x03; p[7] = profile; p[10] = mode }
    }

    static func reportRate(profile: UInt8, rate: UInt8) -> [UInt8] {
        make(.reportRate, 0xAE) { p in p[4] = 0x03; p[7] = profile; p[10] = rate }
    }

    /// stage: 1 tabanlı kademe numarası
    static func dpiStage(profile: UInt8, stage: UInt8, dpi: Int) -> [UInt8] {
        make(.dpiStage, 0xAE) { p in
            p[4] = 0x03; p[7] = profile
            p[10] = stage
            p[11] = UInt8(dpi & 0xFF)
            p[12] = UInt8((dpi >> 8) & 0xFF)
        }
    }

    /// Makro belleğinin bir parçası (en fazla 56 bayt)
    static func macroChunk(offset: Int, data: ArraySlice<UInt8>) -> [UInt8] {
        make(.macroData, 0x00) { p in
            p[4] = UInt8(data.count)
            p[5] = UInt8(offset & 0xFF)
            p[6] = UInt8((offset >> 8) & 0xFF)
            for (i, b) in data.enumerated() { p[8 + i] = b }
        }
    }

    static func macroCommit() -> [UInt8] { make(.macroCommit, 0xA5) }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// 0x0E cevabı / 0x0F isteğiyle aynı düzen. Bilinmeyen baytlar cihazdan okunduğu gibi korunur.
struct MouseConfig: Equatable {
    static let stages = 6
    static let dpiRange = 50...26000
    static let dpiStep = 50

    var raw = [UInt8](repeating: 0, count: 64)

    /// 0 Kapalı, 1-7 sabit renk, 8 döngüsel renk, 9 nefes
    var lightMode: Int {
        get { Int(raw[9]) }
        set { raw[9] = UInt8(clamping: newValue) }
    }

    /// 1=125Hz 2=250Hz 3=500Hz 4=1000Hz
    var reportRate: Int {
        get { Int(raw[10]) }
        set { raw[10] = UInt8(clamping: newValue) }
    }

    /// 0 tabanlı aktif DPI kademesi (cihazda 1 tabanlı saklanır)
    var activeStage: Int {
        get { min(max(Int(raw[12]) - 1, 0), Self.stages - 1) }
        set { raw[12] = UInt8(clamping: min(max(newValue, 0), Self.stages - 1) + 1) }
    }

    func dpi(_ i: Int) -> Int {
        Int(raw[13 + i * 2]) | (Int(raw[14 + i * 2]) << 8)
    }

    mutating func setDpi(_ i: Int, _ value: Int) {
        let v = min(max(value, Self.dpiRange.lowerBound), Self.dpiRange.upperBound)
        raw[13 + i * 2] = UInt8(v & 0xFF)
        raw[14 + i * 2] = UInt8((v >> 8) & 0xFF)
    }

    /// 0=İleri 1=Geri
    var scrollDirection: Int {
        get { Int(raw[48]) }
        set { raw[48] = UInt8(clamping: newValue) }
    }

    /// 1=1mm 2=2mm
    var liftOff: Int {
        get { Int(raw[49]) }
        set { raw[49] = UInt8(clamping: newValue) }
    }

    var sensorBits: UInt8 { raw[50] }

    var rippleControl: Bool {
        get { raw[50] & 0x10 != 0 }
        set { setBit(50, 0x10, newValue) }
    }

    var angleSnap: Bool {
        get { raw[50] & 0x01 != 0 }
        set { setBit(50, 0x01, newValue) }
    }

    var motionSync: Bool {
        get { raw[50] & 0x20 != 0 }
        set { setBit(50, 0x20, newValue) }
    }

    /// Tuş gecikmesi (debounce), ms, 0...20
    var debounce: Int {
        get { Int(raw[51]) }
        set { raw[51] = UInt8(clamping: min(max(newValue, 0), 20)) }
    }

    /// Hazırda bekleme süresi, dakika (255 = bekleme yok)
    var sleepMinutes: Int {
        get { Int(raw[52]) }
        set { raw[52] = UInt8(clamping: newValue) }
    }

    /// 1=Kapalı 2=Açık
    var eSportsRaw: Int { Int(raw[53]) }

    var eSports: Bool {
        get { raw[53] == 2 }
        set { raw[53] = newValue ? 2 : 1 }
    }

    private mutating func setBit(_ idx: Int, _ mask: UInt8, _ on: Bool) {
        if on { raw[idx] |= mask } else { raw[idx] &= ~mask }
    }

    init() {}

    init?(response: [UInt8]) {
        guard response.count >= 64, response[0] == 0xAA, response[1] == Cmd.readConfig.rawValue else { return nil }
        raw = Array(response.prefix(64))
    }

    func writePacket(profile: UInt8) -> [UInt8] {
        var p = raw
        p[0] = 0x55
        p[1] = Cmd.writeConfig.rawValue
        p[2] = 0xAE
        p[4] = 0x2E
        p[5] = 0
        p[6] = 0
        p[7] = profile
        p[8] = profile
        p[11] = UInt8(Self.stages)
        if p[12] < 1 || p[12] > UInt8(Self.stages) { p[12] = 1 }
        p[3] = Packet.checksum(p)
        return p
    }
}

enum Options {
    static let reportRates: [(Int, String)] = [(1, "125 Hz"), (2, "250 Hz"), (3, "500 Hz"), (4, "1000 Hz")]
    static let liftOff: [(Int, String)] = [(1, "1 mm"), (2, "2 mm")]
    static let scroll: [(Int, String)] = [(0, "İleri"), (1, "Geri")]
    static let sleep: [(Int, String)] = [
        (1, "1 dakika"), (3, "3 dakika"), (5, "5 dakika"), (10, "10 dakika"),
        (20, "20 dakika"), (30, "30 dakika"), (60, "1 saat"), (255, "Bekleme yok"),
    ]
    static let dpiPresets = [400, 800, 1200, 1600, 3200, 6400, 12000, 26000]
}
