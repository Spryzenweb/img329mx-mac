import AppKit
import SwiftUI

extension MouseModel {
    func addMacro() -> UUID? {
        guard library.macros.count < MacroCodec.maxMacros else { return nil }
        let m = Macro(name: "Makro \(library.macros.count + 1)")
        editMacros { $0.append(m) }
        return m.id
    }

    /// Makroyu siler; tuş atamalarındaki makro numaralarını da kaydırır.
    func deleteMacro(_ id: UUID) {
        guard let idx = library.macros.firstIndex(where: { $0.id == id }) else { return }
        editMacros { $0.remove(at: idx) }
        for s in 0..<keys.count where keys[s].isMacro {
            let k = keys[s]
            if k.macroIndex == idx {
                keys[s] = KeyMap.defaults[s]
            } else if k.macroIndex > idx {
                keys[s] = .macro(k.macroIndex - 1, count: k.macroCount, mode: k.macroMode)
            }
        }
    }

    func macroBinding(_ id: UUID) -> Binding<Macro>? {
        guard library.macros.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.library.macros.first(where: { $0.id == id }) ?? Macro(name: "") },
            set: { new in
                self.editMacros { ms in
                    if let i = ms.firstIndex(where: { $0.id == id }) { ms[i] = new }
                }
            })
    }

    func slotsUsing(macro idx: Int) -> [String] {
        (0..<keys.count).filter { keys[$0].isMacro && keys[$0].macroIndex == idx }.map { KeyMap.names[$0] }
    }
}

struct MacrosPage: View {
    @EnvironmentObject var model: MouseModel
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            MacroList(selection: $selection)
                .frame(width: 240)
            Divider()
            Group {
                if let id = selection, let b = model.macroBinding(id) {
                    MacroEditor(macro: b, index: model.library.macros.firstIndex(where: { $0.id == id }) ?? 0)
                        .id(id)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "record.circle").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(model.library.macros.isEmpty ? "Henüz makro yok" : "Bir makro seçin").font(.title3)
                        Text("Makro, tek tuşla çalışan bir tuş/tık dizisidir. Oluşturup Mouse Tuşları sayfasında bir tuşa atayın.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                        Button("Yeni makro") { selection = model.addMacro() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = model.library.macros.first?.id }
        }
    }
}

struct MacroList: View {
    @EnvironmentObject var model: MouseModel
    @Binding var selection: UUID?

    var body: some View {
        let used = MacroCodec.size(model.library.macros)
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(Array(model.library.macros.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).lineLimit(1)
                            let slots = model.slotsUsing(macro: i)
                            Text(slots.isEmpty ? "\(m.events.count) olay" : "\(m.events.count) olay · \(slots.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(m.id)
                }
            }
            .listStyle(.inset)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Button { selection = model.addMacro() } label: { Image(systemName: "plus") }
                        .disabled(model.library.macros.count >= MacroCodec.maxMacros)
                        .help("Yeni makro")
                    Button {
                        if let s = selection {
                            let idx = model.library.macros.firstIndex(where: { $0.id == s }) ?? 0
                            model.deleteMacro(s)
                            let ms = model.library.macros
                            selection = ms.isEmpty ? nil : ms[min(idx, ms.count - 1)].id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                        .help("Makroyu sil")
                    Spacer()
                    Text("\(model.library.macros.count)/\(MacroCodec.maxMacros)").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                ProgressView(value: Double(min(used, MacroCodec.maxBytes)), total: Double(MacroCodec.maxBytes))
                    .tint(used > MacroCodec.maxBytes ? .red : .accentColor)
                Text("Fare belleği: \(used) / \(MacroCodec.maxBytes) bayt")
                    .font(.caption).foregroundStyle(used > MacroCodec.maxBytes ? Color.red : Color.secondary)
            }
            .padding(10)
        }
    }
}

struct MacroEditor: View {
    @EnvironmentObject var model: MouseModel
    @Binding var macro: Macro
    let index: Int

    @State private var selection = Set<UUID>()
    @State private var recording = false
    @State private var monitor: Any?
    @State private var lastEventTime: TimeInterval?
    @State private var pressedMods = Set<UInt8>()
    @State private var addingKey = false
    @State private var bulkDelay = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            if macro.events.isEmpty && !recording {
                VStack(spacing: 10) {
                    Image(systemName: "keyboard").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Makro boş").font(.title3)
                    Text("Kayda başla'ya basıp klavyede yazın ya da Ekle menüsünden tuş, tık ve kaydırma ekleyin.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(Array(macro.events.enumerated()), id: \.element.id) { i, e in
                        MacroEventRow(number: i + 1, event: $macro.events[i], isLast: i == macro.events.count - 1)
                            .tag(e.id)
                    }
                    .onMove { macro.events.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { macro.events.remove(atOffsets: $0) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onDeleteCommand { deleteSelected() }
                .overlay(alignment: .bottom) {
                    if recording {
                        Label("Kaydediliyor… klavyede yazın, bitince Durdur'a basın", systemImage: "record.circle.fill")
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.red))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                }
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .sheet(isPresented: $addingKey) {
            KeyRecorderSheet(title: "Makroya tuş ekle") { mods, usage in
                appendKeyPress(mods: mods, usage: usage)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Makro adı", text: $macro.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Label(recording ? "Durdur" : "Kayda başla", systemImage: recording ? "stop.fill" : "record.circle")
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .help("Klavyede bastığınız tuşları gecikmeleriyle birlikte kaydeder")

            Menu {
                Button("Tuş ya da kısayol…") { addingKey = true }
                Divider()
                ForEach(MacroEvent.buttons, id: \.0) { b in
                    Button("\(b.1) (bas + bırak)") {
                        append([.init(kind: .mouseDown, code: b.0, delay: 20), .init(kind: .mouseUp, code: b.0, delay: 20)])
                    }
                }
                Divider()
                Button("Yukarı kaydır") { append([.init(kind: .scroll, code: 0x01, delay: 20)]) }
                Button("Aşağı kaydır") { append([.init(kind: .scroll, code: 0xFF, delay: 20)]) }
                Divider()
                Menu("Tek olay") {
                    ForEach(MacroEvent.buttons, id: \.0) { b in
                        Button("\(b.1) bas") { append([.init(kind: .mouseDown, code: b.0)]) }
                        Button("\(b.1) bırak") { append([.init(kind: .mouseUp, code: b.0)]) }
                    }
                }
            } label: {
                Label("Ekle", systemImage: "plus")
            }
            .fixedSize()
            .disabled(recording)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) { deleteSelected() } label: { Label("Seçileni sil", systemImage: "trash") }
                .disabled(selection.isEmpty)
            Button("Tümünü temizle") { macro.events.removeAll(); selection.removeAll() }
                .disabled(macro.events.isEmpty)
            Spacer()
            Text("Tüm gecikmeler:").foregroundStyle(.secondary)
            TextField("", value: $bulkDelay, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.trailing)
            Text("ms").foregroundStyle(.secondary)
            Button("Uygula") {
                let d = min(max(bulkDelay, 1), 65535)
                for i in macro.events.indices { macro.events[i].delay = d }
            }
            .disabled(macro.events.isEmpty)
        }
        .font(.callout)
        .disabled(recording)
    }

    private func append(_ ev: [MacroEvent]) {
        macro.events += ev
    }

    private func appendKeyPress(mods: UInt8, usage: UInt8) {
        let modUsages: [UInt8] = [(0x01, 0xE0), (0x02, 0xE1), (0x04, 0xE2), (0x08, 0xE3),
                                  (0x10, 0xE4), (0x20, 0xE5), (0x40, 0xE6), (0x80, 0xE7)]
            .filter { mods & $0.0 != 0 }.map(\.1)
        var ev: [MacroEvent] = modUsages.map { .init(kind: .keyDown, code: $0, delay: 20) }
        if usage != 0 {
            ev.append(.init(kind: .keyDown, code: usage, delay: 30))
            ev.append(.init(kind: .keyUp, code: usage, delay: 20))
        }
        ev += modUsages.reversed().map { .init(kind: .keyUp, code: $0, delay: 20) }
        append(ev)
    }

    private func deleteSelected() {
        macro.events.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    // MARK: Kayıt

    private func startRecording() {
        recording = true
        lastEventTime = nil
        pressedMods = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { e in
            // Yazı alanına odaklıysa (ör. makro adı) kayda karışmasın diye tüm tuşlar yutulur.
            guard let u = KeyNames.usage(forKeyCode: e.keyCode) else { return nil }
            switch e.type {
            case .keyDown:
                if e.isARepeat { return nil }
                record(.init(kind: .keyDown, code: u), at: e.timestamp)
            case .keyUp:
                record(.init(kind: .keyUp, code: u), at: e.timestamp)
            case .flagsChanged:
                guard KeyNames.isModifier(u) else { return nil }
                if pressedMods.contains(u) {
                    pressedMods.remove(u)
                    record(.init(kind: .keyUp, code: u), at: e.timestamp)
                } else {
                    pressedMods.insert(u)
                    record(.init(kind: .keyDown, code: u), at: e.timestamp)
                }
            default: break
            }
            return nil
        }
    }

    private func record(_ ev: MacroEvent, at t: TimeInterval) {
        var ev = ev
        ev.delay = 10
        if let last = lastEventTime, !macro.events.isEmpty {
            let ms = Int(((t - last) * 1000).rounded())
            macro.events[macro.events.count - 1].delay = min(max(ms, 1), 65535)
        }
        lastEventTime = t
        macro.events.append(ev)
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Basılı kalan değiştiricileri bırak
        for u in pressedMods { macro.events.append(.init(kind: .keyUp, code: u, delay: 10)) }
        pressedMods = []
        recording = false
    }
}

struct MacroEventRow: View {
    let number: Int
    @Binding var event: MacroEvent
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
            Image(systemName: event.symbol)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(event.title).font(.body.weight(.medium))
            if !event.action.isEmpty {
                Pill(text: event.action, tint: color)
            }
            Spacer()
            Image(systemName: "timer").foregroundStyle(.tertiary)
            TextField("", value: Binding(get: { event.delay }, set: { event.delay = min(max($0, 1), 65535) }),
                      format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
            Text("ms").foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help(isLast ? "Son olaydan sonraki bekleme, tekrarlar arasındaki süredir" : "Bu olaydan sonra beklenecek süre")
    }

    private var color: Color {
        switch event.kind {
        case .keyDown, .mouseDown: return .blue
        case .keyUp, .mouseUp: return .gray
        case .scroll: return .purple
        }
    }
}
