import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Menü çubuğu simgesi

/// Menü çubuğunda: fare simgesi + pil yüzdesi (+ şarjda şimşek). Pil %15 altındaysa kırmızı.
struct TrayLabel: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        Image(nsImage: Self.render(percent: model.trayBattery, charging: model.trayCharging,
                                   present: model.connected || model.bluetoothConnected))
    }

    @MainActor static func render(percent: Int?, charging: Bool, present: Bool) -> NSImage {
        let low = (percent ?? 100) <= 15 && !charging
        let content = HStack(spacing: 3) {
            Image(systemName: present ? "computermouse.fill" : "computermouse")
                .font(.system(size: 12.5, weight: .medium))
            if let p = percent {
                Text("%\(p)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(low ? Color.red : Color.black)
        .padding(.horizontal, 1)
        .frame(height: 18)

        let r = ImageRenderer(content: content)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage ?? NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = !low
        img.accessibilityDescription = percent.map { "IMG-329MX pil yüzde \($0)" } ?? "IMG-329MX"
        return img
    }
}

// MARK: - Menü çubuğu paneli

struct TrayPanel: View {
    @EnvironmentObject var model: MouseModel
    @Environment(\.openWindow) private var openWindow
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MouseImage().frame(width: 28, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("IMG-329MX").font(.headline)
                    HStack(spacing: 5) {
                        Circle().fill(present ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                        Text(model.trayMode).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let p = model.trayBattery {
                    Text("%\(p)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint(p))
                }
            }

            if let p = model.trayBattery {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1))
                            Capsule().fill(tint(p).gradient)
                                .frame(width: max(8, g.size.width * CGFloat(p) / 100))
                        }
                    }
                    .frame(height: 8)
                    HStack(spacing: 4) {
                        if model.trayCharging {
                            Image(systemName: "bolt.fill")
                            Text("Şarj oluyor")
                        } else {
                            Text(remainingText(p))
                        }
                        Spacer()
                        if let d = model.batteryUpdated {
                            Text(d, format: .relative(presentation: .named))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle(isOn: Binding(get: { loginItem }, set: setLoginItem)) {
                Text("Mac açılınca başlat")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Ayarları Aç", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var present: Bool { model.connected || model.bluetoothConnected }

    private var emptyText: String {
        if model.bluetoothConnected {
            return "Pil okunuyor… İlk seferde Bluetooth izni istenir; Sistem Ayarları > Gizlilik ve Güvenlik > Bluetooth'tan IMG-329MX'e izin verin."
        }
        if model.connected { return "Pil okunuyor…" }
        return "Fare bağlı değil. Bluetooth, USB ya da 2.4 GHz alıcıyla bağlayın."
    }

    private func tint(_ p: Int) -> Color {
        if model.trayCharging { return .green }
        switch p {
        case ..<16: return .red
        case ..<31: return .orange
        default: return .green
        }
    }

    private func remainingText(_ p: Int) -> String {
        switch p {
        case ..<16: return "Pil zayıf, şarj edin"
        case ..<31: return "Pil azalıyor"
        default: return "Pil iyi durumda"
        }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Ayarlanamadı: \(error.localizedDescription)"
        }
        loginItem = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginError = "Sistem Ayarları > Genel > Giriş Öğeleri'nden onaylayın."
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

// MARK: - Uygulama davranışı

/// Pencere kapanınca Dock'tan çekilip yalnızca menü çubuğunda kalır;
/// Mac açılışında başlatıldıysa pencere açmadan menü çubuğunda başlar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, Self.isMainWindow(w) else { return }
            DispatchQueue.main.async {
                if !NSApp.windows.contains(where: { $0 !== w && Self.isMainWindow($0) && $0.isVisible }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        if Self.launchedAtLogin() || CommandLine.arguments.contains("--tray") {
            DispatchQueue.main.async {
                NSApp.windows.filter(Self.isMainWindow).forEach { $0.close() }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    static func isMainWindow(_ w: NSWindow) -> Bool {
        !(w is NSPanel) && w.styleMask.contains(.titled)
    }

    private static func launchedAtLogin() -> Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return ev.eventID == AEEventID(kAEOpenApplication)
            && ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
