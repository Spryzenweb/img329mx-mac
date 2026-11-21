import Foundation

struct MacroEvent: Identifiable, Equatable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case keyDown, keyUp, mouseDown, mouseUp, scroll
    }

    var id = UUID()
    var kind: Kind
    /// Klavye: HID kullanım kodu. Fare: tuş maskesi (01 sol, 02 sağ, 04 orta, 08 geri, 10 ileri). Kaydırma: 01 yukarı, FF aşağı.
    var code: UInt8
    /// Bu olaydan sonra beklenecek süre (ms)
    var delay: Int = 30

    var title: String {
        switch kind {
        case .keyDown, .keyUp: return KeyNames.name(code)
        case .mouseDown, .mouseUp: return Self.buttonName(code)
        case .scroll: return code == 0x01 ? "Yukarı kaydır" : "Aşağı kaydır"
        }
    }

    var action: String {
        switch kind {
        case .keyDown, .mouseDown: return "bas"
        case .keyUp, .mouseUp: return "bırak"
        case .scroll: return ""
        }
    }

    var symbol: String {
        switch kind {
        case .keyDown: return "arrow.down.square"
        case .keyUp: return "arrow.up.square"
        case .mouseDown: return "cursorarrow.rays"
        case .mouseUp: return "cursorarrow"
        case .scroll: return code == 0x01 ? "chevron.up.circle" : "chevron.down.circle"
        }
    }

    static let buttons: [(UInt8, String)] = [(0x01, "Sol tık"), (0x02, "Sağ tık"), (0x04, "Orta tık"), (0x08, "Geri"), (0x10, "İleri")]

    static func buttonName(_ c: UInt8) -> String {
        buttons.first(where: { $0.0 == c })?.1 ?? String(format: "Fare %02X", c)
    }
}

struct Macro: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var events: [MacroEvent] = []
}

/// Fare makro belleği: 32 × uint16 başlangıç ofseti, ardından 4 baytlık olaylar (DeviceDriver.exe @ 0x429dd0).
///   olay = [gecikmeLo, gecikmeHi, bayrak, kod], makronun son olayında bayrak |= 0x80
enum MacroCodec {
    static let maxMacros = 32
    static let headerSize = 0x40
    static let maxBytes = 0x1080
    static let chunk = 56

    static func flags(_ e: MacroEvent) -> UInt8 {
        let mod: UInt8 = KeyNames.isModifier(e.code) ? 0x01 : 0x02
        switch e.kind {
        case .keyDown: return 0x40 | mod
        case .keyUp: return mod
        case .mouseDown: return 0x43
        case .mouseUp: return 0x03
        case .scroll: return 0x44
        }
    }

    static func encode(_ macros: [Macro]) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: headerSize)
        for i in 0..<maxMacros {
            let off = buf.count
            buf[i * 2] = UInt8(off & 0xFF)
            buf[i * 2 + 1] = UInt8(off >> 8)
            let events = i < macros.count ? macros[i].events : []
            if events.isEmpty {
                buf += [0, 0, 0x80, 0]
                continue
            }
            for (j, e) in events.enumerated() {
                let d = UInt16(clamping: e.delay <= 0 ? 10 : e.delay)
                var f = flags(e)
                if j == events.count - 1 { f |= 0x80 }
                buf += [UInt8(d & 0xFF), UInt8(d >> 8), f, e.code]
            }
        }
        return buf
    }

    static func size(_ macros: [Macro]) -> Int {
        headerSize + (0..<maxMacros).reduce(0) { n, i in
            n + 4 * max(i < macros.count ? macros[i].events.count : 0, 1)
        }
    }

    static func packets(_ macros: [Macro]) -> [[UInt8]] {
        let buf = encode(macros)
        var out: [[UInt8]] = []
        var off = 0
        while off < buf.count {
            let end = min(off + chunk, buf.count)
            out.append(Packet.macroChunk(offset: off, data: buf[off..<end]))
            off = end
        }
        out.append(Packet.macroCommit())
        return out
    }
}

/// Fare makroları geri okumaya izin vermiyor; makrolar burada saklanır.
struct MacroLibrary: Codable {
    var macros: [Macro] = []
    /// Son yüklemeden sonra değişiklik var mı
    var pendingUpload = false
    /// Bu Mac'ten fareye hiç makro yüklendi mi (ilk yüklemede uyarı göstermek için)
    var everUploaded = false

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IMG-329MX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("macros.json")
    }

    static func load() -> MacroLibrary {
        guard let d = try? Data(contentsOf: url),
              let lib = try? JSONDecoder().decode(MacroLibrary.self, from: d) else { return MacroLibrary() }
        return lib
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(self) { try? d.write(to: Self.url, options: .atomic) }
    }
}
