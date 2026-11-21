import SwiftUI

@main
struct IMG329MXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MouseModel()

    var body: some Scene {
        Window("IMG-329MX", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Fareye Kaydet") { Task { await model.save() } }
                    .keyboardShortcut("s")
                    .disabled(!model.dirty || model.busy || !model.connected)
            }
        }

        MenuBarExtra {
            TrayPanel().environmentObject(model)
        } label: {
            TrayLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: MouseModel

    private var ready: Bool { model.connected && model.loaded }

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                if ready || model.page == .log || model.page == .macros {
                    page
                } else {
                    PlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .safeAreaInset(edge: .bottom, spacing: 0) { SaveBar() }
            .navigationTitle(model.page.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Fareden yeniden oku", systemImage: "arrow.clockwise")
                    }
                    .help("Ayarları fareden yeniden oku")
                    .disabled(!model.connected || model.busy)
                }
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .home: HomePage()
        case .keys: KeysPage()
        case .dpi: DPIPage()
        case .macros: MacrosPage()
        case .lighting: LightingPage()
        case .settings: SettingsPage()
        case .log: LogPage()
        }
    }
}

// MARK: - Kenar çubuğu

struct Sidebar: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        List(selection: Binding<Page?>(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
            Section("Ayarlar") {
                ForEach([Page.home, .keys, .dpi, .macros, .lighting, .settings]) { p in
                    Label(p.title, systemImage: p.symbol).tag(p)
                }
            }
            Section("Gelişmiş") {
                Label(Page.log.title, systemImage: Page.log.symbol).tag(Page.log)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { DeviceBadge().padding(12) }
    }
}

struct DeviceBadge: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        HStack(spacing: 12) {
            MouseImage()
                .frame(width: 30, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("IMG-329MX").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(model.connectionText).font(.caption).foregroundStyle(.secondary)
                }
                if let b = model.battery, model.connected {
                    HStack(spacing: 4) {
                        Image(systemName: model.charging ? "battery.100.bolt" : batteryIcon(b))
                        Text("%\(b)").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

func batteryIcon(_ p: Int) -> String {
    switch p {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
}

extension MouseModel {
    var connectionText: String {
        if connected { return isWireless ? "2.4 GHz alıcı" : "USB kablo" }
        return bluetoothConnected ? "Bluetooth (ayar yapılamaz)" : "Bağlı değil"
    }
}

// MARK: - Kaydet çubuğu

struct SaveBar: View {
    @EnvironmentObject var model: MouseModel
    @State private var confirmMacros = false

    var body: some View {
        HStack(spacing: 12) {
            if model.busy {
                ProgressView().controlSize(.small)
            } else if !model.status.isEmpty {
                Image(systemName: model.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(model.statusIsError ? Color.orange : Color.secondary)
            }
            Text(model.status)
                .font(.callout)
                .foregroundStyle(model.statusIsError ? Color.primary : Color.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
            if model.dirty {
                Text(pendingText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Geri Al") { model.revert() }
                    .disabled(model.busy || (!model.configDirty && !model.keysDirty))
            }
            Button {
                if model.macrosDirty && !model.library.everUploaded && !model.demo {
                    confirmMacros = true
                } else {
                    Task { await model.save() }
                }
            } label: {
                Label("Fareye Kaydet", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.dirty || model.busy || !model.connected || !model.loaded)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .alert("Makrolar fareye yüklensin mi?", isPresented: $confirmMacros) {
            Button("Yükle ve Kaydet") { Task { await model.save() } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Fare makroları geri okumaya izin vermediği için farede daha önce (ör. Windows'ta) kaydedilmiş makroların üzerine bu Mac'teki makro listesi yazılacak.")
        }
    }

    private var pendingText: String {
        var parts: [String] = []
        if model.configDirty { parts.append("ayarlar") }
        if model.keysDirty { parts.append("tuşlar") }
        if model.macrosDirty { parts.append("makrolar") }
        return "Kaydedilmedi: " + parts.joined(separator: ", ")
    }
}

// MARK: - Bağlı değil

struct PlaceholderView: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        VStack(spacing: 14) {
            if model.busy {
                ProgressView()
                Text("Fare okunuyor…").foregroundStyle(.secondary)
            } else if !model.connected && model.bluetoothConnected {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 44)).foregroundStyle(.blue)
                Text("Fare Bluetooth ile bağlı").font(.title2.weight(.semibold))
                Text("Bluetooth bağlantısında fare ayar kanalını açmıyor (orijinal Windows yazılımı da yalnızca USB ve 2.4 GHz alıcıyı destekliyor).\n\nAyarları değiştirmek için USB kablosunu ya da 2.4 GHz alıcıyı takın. Kaydettiğiniz her şey farenin hafızasında kalır; sonra Bluetooth'a geri dönebilirsiniz.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
            } else {
                MouseImage().frame(width: 70, height: 128).opacity(0.5)
                Text(model.connected ? "Fare ayarları okunamadı" : "Lütfen fareyi bağlayın")
                    .font(.title2.weight(.semibold))
                Text(model.connected
                     ? "Fareyi hareket ettirip tekrar deneyin."
                     : "USB kablosunu ya da 2.4 GHz alıcıyı takın. Fare otomatik olarak algılanır.")
                    .foregroundStyle(.secondary)
                if model.connected {
                    Button("Tekrar dene") { Task { await model.refresh() } }
                        .controlSize(.large)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
