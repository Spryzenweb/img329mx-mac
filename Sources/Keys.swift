import AppKit
import Foundation

/// Tuş ataması: farenin hafızasındaki 4 baytlık kayıt (komut 08 / 09).
struct KeyBinding: Equatable, Hashable, Codable {
    var b: [UInt8]

    init(_ bytes: [UInt8]) {
        var x = Array(bytes.prefix(4))
        while x.count < 4 { x.append(0) }
        b = x
    }

    // MARK: Kurucular

    static func mouse(_ mask: UInt8) -> KeyBinding { .init([0x20, mask]) }
    static let doubleClick = KeyBinding([0x20, 0x01, 0x02])
    static let scrollUp = KeyBinding([0x21, 0x38, 0x01])
    static let scrollDown = KeyBinding([0x21, 0x38, 0xFF])
    static let dpiButton = KeyBinding([0x21, 0x55])
    static let dpiUp = KeyBinding([0xF0, 0x01, 0x01])
    static let dpiDown = KeyBinding([0xF0, 0x01, 0x02])
    static let dpiLoop = KeyBinding([0xF0, 0x01, 0x03])
    static let rateUp = KeyBinding([0xF0, 0x02, 0x01])
    static let rateDown = KeyBinding([0xF0, 0x02, 0x02])
    static let rateLoop = KeyBinding([0xF0, 0x02, 0x03])

    static func keyboard(mods: UInt8, usage: UInt8) -> KeyBinding { .init([0x10, mods, usage]) }
    static func media(_ usage: UInt16) -> KeyBinding { .init([0x30, UInt8(usage & 0xFF), UInt8(usage >> 8)]) }

    /// mode: 0 = belirtilen sayı kadar, 2 = bırakılana kadar tekrar, 3 = herhangi bir tuşa basılana kadar tekrar
    static func macro(_ index: Int, count: Int, mode: UInt8) -> KeyBinding {
        .init([0x70, UInt8(clamping: index), UInt8(clamping: max(count, 1)), mode])
    }

    /// Devre dışı: orijinal yazılım ilk baytı 0 yapıp kalanı varsayılandan bırakır.
    static func disabled(slot: Int) -> KeyBinding {
        var d = KeyMap.defaults[slot].b
        d[0] = 0
        return .init(d)
    }

    // MARK: Çözümleme

    var isDisabled: Bool { b[0] == 0x00 }
    var isMacro: Bool { b[0] == 0x70 }
    var isKeyboard: Bool { b[0] == 0x10 }
    var macroIndex: Int { Int(b[1]) }
    var macroCount: Int { Int(b[2]) }
    var macroMode: UInt8 { b[3] }

    var title: String {
        if isDisabled { return "Devre dışı" }
        if let p = KeyCatalog.all.first(where: { $0.binding == self }) { return p.title }
        switch b[0] {
        case 0x10: return KeyNames.combo(mods: b[1], usage: b[2])
        case 0x20: return "Fare tuşu (\(String(format: "%02X", b[1])))"
        case 0x30:
            let u = UInt16(b[1]) | UInt16(b[2]) << 8
            return "Multimedya (\(String(format: "%03X", u)))"
        case 0x70: return "Makro \(Int(b[1]) + 1)"
        default: return "Özel (\(Packet.hex(b)))"
        }
    }

    var symbol: String {
        if isDisabled { return "nosign" }
        if let p = KeyCatalog.all.first(where: { $0.binding == self }) { return p.symbol }
        switch b[0] {
        case 0x10: return "keyboard"
        case 0x30: return "play.rectangle"
        case 0x70: return "record.circle"
        default: return "questionmark.circle"
        }
    }
}

enum KeyMap {
    static let slots = 8

    /// Fabrika ayarları (DeviceDriver.exe @ 0x42a610)
    static let defaults: [KeyBinding] = [
        .mouse(0x01), .mouse(0x02), .mouse(0x04), .mouse(0x08), .mouse(0x10),
        .dpiButton, .scrollUp, .scrollDown,
    ]

    static let names = [
        "Sol tuş", "Sağ tuş", "Orta tuş", "Geri tuşu", "İleri tuşu",
        "DPI tuşu", "Tekerlek yukarı", "Tekerlek aşağı",
    ]

    static let hints = [
        "Ana tıklama", "İkincil tıklama", "Tekerleğe basma", "Yan tuş (arkadaki)", "Yan tuş (öndeki)",
        "Tekerleğin arkasındaki tuş", "Tekerleği yukarı çevirme", "Tekerleği aşağı çevirme",
    ]

    static let symbols = [
        "computermouse", "computermouse", "circle.circle", "arrow.uturn.backward", "arrow.uturn.forward",
        "gauge.with.dots.needle.50percent", "chevron.up", "chevron.down",
    ]

    static func parse(_ r: [UInt8]) -> [KeyBinding]? {
        guard r.count >= 8 + slots * 4, r[0] == 0xAA, r[1] == Cmd.readKeys.rawValue else { return nil }
        return (0..<slots).map { i in KeyBinding(Array(r[(8 + i * 4)..<(12 + i * 4)])) }
    }
}

struct KeyPreset: Identifiable, Hashable {
    let title: String
    let symbol: String
    let binding: KeyBinding
    var id: KeyBinding { binding }
}

struct KeyGroup: Identifiable {
    let title: String
    let symbol: String
    let items: [KeyPreset]
    var id: String { title }
}

enum KeyCatalog {
    static let groups: [KeyGroup] = [
        KeyGroup(title: "Fare", symbol: "computermouse", items: [
            .init(title: "Sol tık", symbol: "computermouse", binding: .mouse(0x01)),
            .init(title: "Sağ tık", symbol: "computermouse", binding: .mouse(0x02)),
            .init(title: "Orta tık", symbol: "circle.circle", binding: .mouse(0x04)),
            .init(title: "Geri", symbol: "arrow.uturn.backward", binding: .mouse(0x08)),
            .init(title: "İleri", symbol: "arrow.uturn.forward", binding: .mouse(0x10)),
            .init(title: "Çift tık", symbol: "cursorarrow.click.2", binding: .doubleClick),
            .init(title: "Yukarı kaydır", symbol: "chevron.up", binding: .scrollUp),
            .init(title: "Aşağı kaydır", symbol: "chevron.down", binding: .scrollDown),
        ]),
        KeyGroup(title: "DPI", symbol: "gauge.with.dots.needle.50percent", items: [
            .init(title: "DPI tuşu (fabrika)", symbol: "gauge.with.dots.needle.50percent", binding: .dpiButton),
            .init(title: "DPI döngüsü", symbol: "arrow.triangle.2.circlepath", binding: .dpiLoop),
            .init(title: "DPI +", symbol: "plus.circle", binding: .dpiUp),
            .init(title: "DPI −", symbol: "minus.circle", binding: .dpiDown),
        ]),
        KeyGroup(title: "Algılama hızı", symbol: "waveform.path", items: [
            .init(title: "Algılama hızı döngüsü", symbol: "arrow.triangle.2.circlepath", binding: .rateLoop),
            .init(title: "Algılama hızı +", symbol: "plus.circle", binding: .rateUp),
            .init(title: "Algılama hızı −", symbol: "minus.circle", binding: .rateDown),
        ]),
        KeyGroup(title: "Multimedya", symbol: "play.rectangle", items: [
            .init(title: "Oynat / Duraklat", symbol: "playpause", binding: .media(0xCD)),
            .init(title: "Durdur", symbol: "stop", binding: .media(0xB7)),
            .init(title: "Önceki parça", symbol: "backward.end", binding: .media(0xB6)),
            .init(title: "Sonraki parça", symbol: "forward.end", binding: .media(0xB5)),
            .init(title: "Ses +", symbol: "speaker.plus", binding: .media(0xE9)),
            .init(title: "Ses −", symbol: "speaker.minus", binding: .media(0xEA)),
            .init(title: "Sessiz", symbol: "speaker.slash", binding: .media(0xE2)),
            .init(title: "Parlaklık +", symbol: "sun.max", binding: .media(0x6F)),
            .init(title: "Parlaklık −", symbol: "sun.min", binding: .media(0x70)),
            .init(title: "Medya oynatıcı", symbol: "music.note", binding: .media(0x183)),
            .init(title: "Hesap makinesi", symbol: "plusminus", binding: .media(0x192)),
            .init(title: "Posta", symbol: "envelope", binding: .media(0x18A)),
            .init(title: "Tarayıcı ana sayfası", symbol: "house", binding: .media(0x223)),
        ]),
        KeyGroup(title: "Kısayollar (macOS)", symbol: "command", items: [
            .init(title: "Kopyala  ⌘C", symbol: "doc.on.doc", binding: .keyboard(mods: 0x08, usage: 0x06)),
            .init(title: "Yapıştır  ⌘V", symbol: "doc.on.clipboard", binding: .keyboard(mods: 0x08, usage: 0x19)),
            .init(title: "Kes  ⌘X", symbol: "scissors", binding: .keyboard(mods: 0x08, usage: 0x1B)),
            .init(title: "Geri al  ⌘Z", symbol: "arrow.uturn.backward.circle", binding: .keyboard(mods: 0x08, usage: 0x1D)),
            .init(title: "Yinele  ⇧⌘Z", symbol: "arrow.uturn.forward.circle", binding: .keyboard(mods: 0x0A, usage: 0x1D)),
            .init(title: "Uygulama değiştir  ⌘Tab", symbol: "square.on.square", binding: .keyboard(mods: 0x08, usage: 0x2B)),
            .init(title: "Sekmeyi kapat  ⌘W", symbol: "xmark.square", binding: .keyboard(mods: 0x08, usage: 0x1A)),
            .init(title: "Ekran görüntüsü  ⇧⌘4", symbol: "camera.viewfinder", binding: .keyboard(mods: 0x0A, usage: 0x21)),
            .init(title: "Spotlight  ⌘Boşluk", symbol: "magnifyingglass", binding: .keyboard(mods: 0x08, usage: 0x2C)),
            .init(title: "Mission Control  ⌃↑", symbol: "rectangle.3.group", binding: .keyboard(mods: 0x01, usage: 0x52)),
            .init(title: "Önceki masaüstü  ⌃←", symbol: "arrow.left.square", binding: .keyboard(mods: 0x01, usage: 0x50)),
            .init(title: "Sonraki masaüstü  ⌃→", symbol: "arrow.right.square", binding: .keyboard(mods: 0x01, usage: 0x4F)),
        ]),
        KeyGroup(title: "Kısayollar (Windows)", symbol: "pc", items: [
            .init(title: "Kopyala  Ctrl+C", symbol: "doc.on.doc", binding: .keyboard(mods: 0x01, usage: 0x06)),
            .init(title: "Yapıştır  Ctrl+V", symbol: "doc.on.clipboard", binding: .keyboard(mods: 0x01, usage: 0x19)),
            .init(title: "Kes  Ctrl+X", symbol: "scissors", binding: .keyboard(mods: 0x01, usage: 0x1B)),
            .init(title: "Alt+Tab", symbol: "square.on.square", binding: .keyboard(mods: 0x04, usage: 0x2B)),
            .init(title: "Masaüstünü göster  Win+D", symbol: "menubar.dock.rectangle", binding: .keyboard(mods: 0x08, usage: 0x07)),
            .init(title: "Dosya gezgini  Win+E", symbol: "folder", binding: .keyboard(mods: 0x08, usage: 0x08)),
            .init(title: "Yenile  F5", symbol: "arrow.clockwise", binding: .keyboard(mods: 0, usage: 0x3E)),
        ]),
    ]

    static let all: [KeyPreset] = groups.flatMap(\.items)
}

enum MacroMode {
    static let options: [(UInt8, String)] = [
        (0, "Belirtilen sayı kadar"),
        (2, "Tuş bırakılana kadar tekrarla"),
        (3, "Herhangi bir tuşa basılana kadar tekrarla"),
    ]
}

/// macOS sanal tuş kodu → USB HID klavye kullanım kodu, ve görünen adlar.
enum KeyNames {
    static let modifierBits: [UInt8: UInt8] = [
        0xE0: 0x01, 0xE1: 0x02, 0xE2: 0x04, 0xE3: 0x08,
        0xE4: 0x10, 0xE5: 0x20, 0xE6: 0x40, 0xE7: 0x80,
    ]

    static func isModifier(_ usage: UInt8) -> Bool { (0xE0...0xE7).contains(usage) }

    static func usage(forKeyCode k: UInt16) -> UInt8? { macToHID[k] }

    static let macToHID: [UInt16: UInt8] = [
        0x00: 0x04, 0x01: 0x16, 0x02: 0x07, 0x03: 0x09, 0x04: 0x0B, 0x05: 0x0A, 0x06: 0x1D, 0x07: 0x1B,
        0x08: 0x06, 0x09: 0x19, 0x0A: 0x64, 0x0B: 0x05, 0x0C: 0x14, 0x0D: 0x1A, 0x0E: 0x08, 0x0F: 0x15,
        0x10: 0x1C, 0x11: 0x17, 0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x16: 0x23, 0x17: 0x22,
        0x18: 0x2E, 0x19: 0x26, 0x1A: 0x24, 0x1B: 0x2D, 0x1C: 0x25, 0x1D: 0x27, 0x1E: 0x30, 0x1F: 0x12,
        0x20: 0x18, 0x21: 0x2F, 0x22: 0x0C, 0x23: 0x13, 0x24: 0x28, 0x25: 0x0F, 0x26: 0x0D, 0x27: 0x34,
        0x28: 0x0E, 0x29: 0x33, 0x2A: 0x31, 0x2B: 0x36, 0x2C: 0x38, 0x2D: 0x11, 0x2E: 0x10, 0x2F: 0x37,
        0x30: 0x2B, 0x31: 0x2C, 0x32: 0x35, 0x33: 0x2A, 0x35: 0x29, 0x36: 0xE7, 0x37: 0xE3, 0x38: 0xE1,
        0x39: 0x39, 0x3A: 0xE2, 0x3B: 0xE0, 0x3C: 0xE5, 0x3D: 0xE6, 0x3E: 0xE4,
        0x40: 0x6C, 0x41: 0x63, 0x43: 0x55, 0x45: 0x57, 0x47: 0x53, 0x4B: 0x54, 0x4C: 0x58, 0x4E: 0x56,
        0x4F: 0x6D, 0x50: 0x6E, 0x51: 0x67, 0x52: 0x62, 0x53: 0x59, 0x54: 0x5A, 0x55: 0x5B, 0x56: 0x5C,
        0x57: 0x5D, 0x58: 0x5E, 0x59: 0x5F, 0x5A: 0x6F, 0x5B: 0x60, 0x5C: 0x61,
        0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x63: 0x3C, 0x64: 0x41, 0x65: 0x42, 0x67: 0x44, 0x69: 0x68,
        0x6A: 0x6B, 0x6B: 0x69, 0x6D: 0x43, 0x6F: 0x45, 0x71: 0x6A, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B,
        0x75: 0x4C, 0x76: 0x3D, 0x77: 0x4D, 0x78: 0x3B, 0x79: 0x4E, 0x7A: 0x3A, 0x7B: 0x50, 0x7C: 0x4F,
        0x7D: 0x51, 0x7E: 0x52,
    ]

    static func name(_ u: UInt8) -> String {
        switch u {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(65) + (u - 0x04)))
        case 0x1E...0x26: return String(u - 0x1D)
        case 0x27: return "0"
        case 0x3A...0x45: return "F\(u - 0x39)"
        case 0x68...0x73: return "F\(u - 0x68 + 13)"
        case 0x59...0x61: return "Num\(u - 0x58)"
        default: break
        }
        let special: [UInt8: String] = [
            0x28: "Return", 0x29: "Esc", 0x2A: "Sil ⌫", 0x2B: "Tab", 0x2C: "Boşluk", 0x2D: "-", 0x2E: "=",
            0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".",
            0x38: "/", 0x39: "Caps Lock", 0x46: "PrtSc", 0x47: "Scroll Lock", 0x48: "Pause", 0x49: "Insert",
            0x4A: "Home", 0x4B: "Page Up", 0x4C: "Sil ⌦", 0x4D: "End", 0x4E: "Page Down", 0x4F: "→",
            0x50: "←", 0x51: "↓", 0x52: "↑", 0x53: "Num Lock", 0x54: "Num /", 0x55: "Num *", 0x56: "Num -",
            0x57: "Num +", 0x58: "Num Enter", 0x62: "Num0", 0x63: "Num .", 0x64: "<>", 0x67: "Num =",
            0xE0: "Control", 0xE1: "Shift", 0xE2: "Option", 0xE3: "Command",
            0xE4: "Sağ Control", 0xE5: "Sağ Shift", 0xE6: "Sağ Option", 0xE7: "Sağ Command",
        ]
        return special[u] ?? String(format: "Tuş %02X", u)
    }

    static func modSymbols(_ m: UInt8) -> String {
        var s = ""
        if m & 0x11 != 0 { s += "⌃" }
        if m & 0x44 != 0 { s += "⌥" }
        if m & 0x22 != 0 { s += "⇧" }
        if m & 0x88 != 0 { s += "⌘" }
        return s
    }

    static func combo(mods: UInt8, usage: UInt8) -> String {
        let m = modSymbols(mods)
        if usage == 0 { return m.isEmpty ? "Tuş yok" : m }
        return m.isEmpty ? name(usage) : "\(m) \(name(usage))"
    }

    /// NSEvent bayraklarından sol taraf HID değiştirici bitleri
    static func modBits(_ f: NSEvent.ModifierFlags) -> UInt8 {
        var m: UInt8 = 0
        if f.contains(.control) { m |= 0x01 }
        if f.contains(.shift) { m |= 0x02 }
        if f.contains(.option) { m |= 0x04 }
        if f.contains(.command) { m |= 0x08 }
        return m
    }
}
