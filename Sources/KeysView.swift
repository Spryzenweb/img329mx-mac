import AppKit
import SwiftUI

struct KeysPage: View {
    @EnvironmentObject var model: MouseModel
    @State private var recordingSlot: Int?

    var body: some View {
        PageScroll(subtitle: "Her tuşa farklı bir görev atayın: fare tıklaması, DPI, multimedya, klavye kısayolu ya da makro.") {
            if !model.keys.contains(.mouse(0x01)) {
                Label("Hiçbir tuş sol tık olarak atanmamış. Kaydederseniz fareyle tıklayamazsınız.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }

            Card("Tuş atamaları", symbol: "computermouse",
                 trailing: AnyView(
                    Button("Tümünü varsayılana döndür") { model.keys = KeyMap.defaults }
                        .disabled(model.keys == KeyMap.defaults))) {
                VStack(spacing: 0) {
                    ForEach(0..<KeyMap.slots, id: \.self) { i in
                        KeyRow(slot: i, onRecord: { recordingSlot = i })
                        if i < KeyMap.slots - 1 { Divider().padding(.leading, 52) }
                    }
                }
            }

            Text("Atamalar farenin hafızasına yazılır ve USB, 2.4 GHz ve Bluetooth bağlantılarında aynı çalışır.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: Binding(get: { recordingSlot.map(SlotID.init) }, set: { recordingSlot = $0?.id })) { s in
            KeyRecorderSheet(title: "\(KeyMap.names[s.id]) için tuş kombinasyonu") { mods, usage in
                model.keys[s.id] = .keyboard(mods: mods, usage: usage)
            }
        }
    }
}

private struct SlotID: Identifiable { let id: Int }

struct KeyRow: View {
    @EnvironmentObject var model: MouseModel
    let slot: Int
    let onRecord: () -> Void

    var body: some View {
        let binding = model.keys[slot]
        let changed = model.keysLoaded && binding != model.deviceKeys[slot]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: KeyMap.symbols[slot])
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(KeyMap.names[slot]).font(.body.weight(.medium))
                        if changed { Circle().fill(Color.orange).frame(width: 6, height: 6).help("Kaydedilmedi") }
                    }
                    Text(KeyMap.hints[slot]).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if binding != KeyMap.defaults[slot] {
                    Button {
                        model.keys[slot] = KeyMap.defaults[slot]
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Varsayılana döndür")
                }
                functionMenu(binding)
            }
            if binding.isMacro { macroOptions(binding) }
        }
        .padding(.vertical, 10)
    }

    private func title(_ b: KeyBinding) -> String {
        if b.isMacro {
            let ms = model.library.macros
            return b.macroIndex < ms.count ? "Makro: \(ms[b.macroIndex].name)" : "Makro \(b.macroIndex + 1) (bu Mac'te yok)"
        }
        return b.title
    }

    private func functionMenu(_ binding: KeyBinding) -> some View {
        Menu {
            ForEach(KeyCatalog.groups) { g in
                Menu {
                    ForEach(g.items) { p in
                        Button { model.keys[slot] = p.binding } label: { Label(p.title, systemImage: p.symbol) }
                    }
                } label: {
                    Label(g.title, systemImage: g.symbol)
                }
            }
            Menu {
                if model.library.macros.isEmpty {
                    Button("Önce Makrolar sayfasında makro oluşturun") { model.page = .macros }
                }
                ForEach(Array(model.library.macros.enumerated()), id: \.element.id) { i, m in
                    Button(m.name) { model.keys[slot] = .macro(i, count: 1, mode: 0) }
                }
            } label: {
                Label("Makro", systemImage: "record.circle")
            }
            Button { onRecord() } label: { Label("Klavye tuşu / kısayol kaydet…", systemImage: "keyboard") }
            Divider()
            Button { model.keys[slot] = KeyMap.defaults[slot] } label: {
                Label("Varsayılan: \(KeyMap.defaults[slot].title)", systemImage: "arrow.uturn.backward")
            }
            Button { model.keys[slot] = .disabled(slot: slot) } label: { Label("Devre dışı", systemImage: "nosign") }
        } label: {
            Label(title(binding), systemImage: binding.symbol)
        }
        .menuStyle(.button)
        .frame(width: 250)
    }

    private func macroOptions(_ b: KeyBinding) -> some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 34)
            Picker("Çalışma", selection: Binding(
                get: { b.macroMode },
                set: { model.keys[slot] = .macro(b.macroIndex, count: b.macroCount, mode: $0) })) {
                ForEach(MacroMode.options, id: \.0) { Text($0.1).tag($0.0) }
                if !MacroMode.options.contains(where: { $0.0 == b.macroMode }) {
                    Text("Bilinmiyor (\(b.macroMode))").tag(b.macroMode)
                }
            }
            .frame(maxWidth: 360)
            if b.macroMode == 0 {
                Stepper(value: Binding(
                    get: { b.macroCount },
                    set: { model.keys[slot] = .macro(b.macroIndex, count: $0, mode: 0) }), in: 1...255) {
                    Text("\(b.macroCount) kez").monospacedDigit()
                }
            }
            Spacer()
        }
        .font(.callout)
    }
}

// MARK: - Tuş kaydedici

/// Klavyeden bir tuş ya da kombinasyon yakalar. Yalnızca değiştirici tuşa (ör. ⌘) basılırsa o da atanabilir.
struct KeyRecorderSheet: View {
    let title: String
    let onDone: (UInt8, UInt8) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mods: UInt8 = 0
    @State private var peakMods: UInt8 = 0
    @State private var usage: UInt8?
    @State private var monitor: Any?
    @State private var unknown = false

    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(.headline)
            Text("Atamak istediğiniz tuşa ya da kombinasyona basın.")
                .foregroundStyle(.secondary)
            Text(display)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .frame(minWidth: 280, minHeight: 70)
                .padding(.horizontal, 20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5))
            if unknown {
                Text("Bu tuş desteklenmiyor (ör. fn ya da medya tuşu).").font(.caption).foregroundStyle(.orange)
            } else {
                Text("⌘ Command, ⌥ Option, ⌃ Control, ⇧ Shift. Windows'ta ⌘ = Win tuşu, ⌥ = Alt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Temizle") { usage = nil; peakMods = 0; mods = 0; unknown = false }
                Spacer()
                Button("İptal") { dismiss() }
                Button("Ata") {
                    onDone(usage == nil ? peakMods : mods, usage ?? 0)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(usage == nil && peakMods == 0)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private var display: String {
        if let usage { return KeyNames.combo(mods: mods, usage: usage) }
        let m = mods != 0 ? mods : peakMods
        return m == 0 ? "…" : KeyNames.modSymbols(m)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .flagsChanged {
                let m = KeyNames.modBits(e.modifierFlags)
                if usage == nil {
                    if m == 0 { mods = 0 } else { mods = m; peakMods |= m }
                }
                return nil
            }
            if e.isARepeat { return nil }
            if let u = KeyNames.usage(forKeyCode: e.keyCode), !KeyNames.isModifier(u) {
                usage = u
                mods = KeyNames.modBits(e.modifierFlags)
                unknown = false
            } else {
                unknown = true
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
