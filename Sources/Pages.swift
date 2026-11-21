import SwiftUI

// MARK: - Ana Sayfa

struct HomePage: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        let c = model.config
        PageScroll {
            Card {
                HStack(alignment: .center, spacing: 28) {
                    GlowingMouse(mode: c.lightMode, height: 210)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("IMG-329MX").font(.system(size: 30, weight: .bold, design: .rounded))
                            HStack(spacing: 8) {
                                Pill(text: model.connectionText, tint: .green)
                                if let fw = model.firmware { Pill(text: "Ürün yazılımı \(fw)") }
                                if c.eSports { Pill(text: "E-Spor modu", tint: .orange) }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                                  spacing: 10) {
                            StatTile(title: "Pil", value: model.battery.map { "%\($0)" } ?? "—",
                                     detail: model.charging ? "Şarj oluyor" : "Pil ile çalışıyor",
                                     symbol: model.charging ? "battery.100.bolt" : batteryIcon(model.battery ?? 0),
                                     tint: .green)
                            StatTile(title: "DPI", value: "\(c.dpi(c.activeStage))",
                                     detail: "Kademe \(c.activeStage + 1) / \(MouseConfig.stages)",
                                     symbol: "gauge.with.dots.needle.67percent")
                            StatTile(title: "Algılama hızı",
                                     value: Options.reportRates.first(where: { $0.0 == c.reportRate })?.1 ?? "—",
                                     detail: "Rapor hızı", symbol: "waveform.path", tint: .purple)
                            StatTile(title: "Işık", value: Lighting.name(c.lightMode),
                                     detail: sleepText(c.sleepMinutes), symbol: "lightbulb", tint: .yellow,
                                     accessory: AnyView(LightDot(mode: c.lightMode, size: 12)))
                        }
                    }
                }
            }

            Card("Hızlı DPI seçimi", symbol: "dial.medium") {
                HStack(spacing: 10) {
                    ForEach(0..<MouseConfig.stages, id: \.self) { i in
                        let active = c.activeStage == i
                        Button {
                            model.config.activeStage = i
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(c.dpi(i))").font(.system(.title3, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                Text("Kademe \(i + 1)").font(.caption)
                                    .foregroundStyle(active ? Color.white.opacity(0.85) : Color.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(active ? Color.accentColor : Color.primary.opacity(0.05)))
                            .foregroundStyle(active ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                OptionPicker(title: "Algılama hızı", value: $model.config.reportRate, options: Options.reportRates)
                    .pickerStyle(.segmented)
            }

            Card("Kısayollar", symbol: "square.grid.2x2") {
                HStack(spacing: 10) {
                    shortcut(.keys, "Tuşları ata", "Her tuşa farklı bir görev")
                    shortcut(.macros, "Makro oluştur", "Tuş dizileri kaydet")
                    shortcut(.lighting, "Işık rengi", "\(Lighting.modes.count) seçenek")
                }
            }

            if model.bluetoothConnected || model.isWireless {
                Label("Ayarlar farenin hafızasına kaydedilir. Bluetooth'a geçtiğinizde de aynen çalışır; ancak Bluetooth üzerinden ayar değiştirilemez.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortcut(_ p: Page, _ title: String, _ detail: String) -> some View {
        Button {
            model.page = p
        } label: {
            HStack(spacing: 10) {
                Image(systemName: p.symbol).font(.title3).frame(width: 28)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sleepText(_ m: Int) -> String {
        if m == 255 { return "Hazırda bekleme yok" }
        return "Bekleme: " + (Options.sleep.first(where: { $0.0 == m })?.1 ?? "\(m) dk")
    }
}

// MARK: - DPI

struct DPIPage: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        PageScroll(subtitle: "DPI tuşu bu 6 kademe arasında geçiş yapar. Daireye tıklayarak başlangıç kademesini seçin.") {
            Card("DPI kademeleri", symbol: "gauge.with.dots.needle.67percent") {
                VStack(spacing: 0) {
                    ForEach(0..<MouseConfig.stages, id: \.self) { i in
                        DPIRow(index: i)
                        if i < MouseConfig.stages - 1 { Divider().padding(.leading, 40) }
                    }
                }
            }
            Card("Algılama hızı", symbol: "waveform.path") {
                OptionPicker(title: "Algılama hızı", value: $model.config.reportRate, options: Options.reportRates)
                    .pickerStyle(.segmented)
                    .labelsHidden()
                Text("Yüksek değer daha akıcı hareket sağlar, kablosuzda pili daha çabuk tüketir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DPIRow: View {
    @EnvironmentObject var model: MouseModel
    let index: Int

    var body: some View {
        let active = model.config.activeStage == index
        let dpi = model.dpiBinding(index)
        HStack(spacing: 14) {
            Button {
                model.config.activeStage = index
            } label: {
                ZStack {
                    Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.06))
                    Text("\(index + 1)").font(.callout.weight(.semibold))
                        .foregroundStyle(active ? Color.white : Color.secondary)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Başlangıç kademesi yap")

            Slider(
                value: Binding(get: { Double(dpi.wrappedValue) },
                               set: { dpi.wrappedValue = Int(($0 / Double(MouseConfig.dpiStep)).rounded()) * MouseConfig.dpiStep }),
                in: Double(MouseConfig.dpiRange.lowerBound)...Double(MouseConfig.dpiRange.upperBound))

            Menu {
                ForEach(Options.dpiPresets, id: \.self) { v in
                    Button("\(v) DPI") { dpi.wrappedValue = v }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Hazır değerler")

            HStack(spacing: 4) {
                TextField("", value: dpi, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                Stepper("", value: dpi, in: MouseConfig.dpiRange, step: MouseConfig.dpiStep).labelsHidden()
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Işıklandırma

struct LightingPage: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        let mode = model.config.lightMode
        PageScroll {
            Card {
                HStack(spacing: 28) {
                    GlowingMouse(mode: mode, height: 190)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seçili ışık").font(.caption).foregroundStyle(.secondary)
                        Text(Lighting.name(mode)).font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(description(mode)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Card("Renk ve efekt", symbol: "paintpalette") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(Lighting.modes) { m in
                        swatch(m, selected: m.id == mode)
                    }
                }
                if !Lighting.modes.contains(where: { $0.id == mode }) {
                    Text("Fare şu an bilinmeyen bir ışık modunda (\(mode)).").font(.caption).foregroundStyle(.orange)
                }
                Text("Bu fare tek renkli LED kullanır; ışık rengi ve efekti buradan seçilir. DPI kademeleri için ayrı renk desteklenmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Card("Hazırda bekleme", symbol: "moon.zzz") {
                SettingRow(title: "Bekleme süresi",
                           subtitle: "Fare bu süre boyunca kullanılmazsa ışığı kapatıp uykuya geçer.") {
                    OptionPicker(title: "", value: $model.config.sleepMinutes, options: Options.sleep)
                        .labelsHidden()
                        .frame(width: 160)
                }
            }
        }
    }

    private func swatch(_ m: Lighting.Mode, selected: Bool) -> some View {
        Button {
            model.config.lightMode = m.id
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    LightDot(mode: m.id, size: 40)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(m.id == 7 || m.id == 5 || m.id == 0 ? Color.black : Color.white)
                            .shadow(radius: 1)
                    }
                }
                Text(m.name).font(.callout).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func description(_ m: Int) -> String {
        switch m {
        case 0: return "Işık kapalı. Pil ömrünü en çok bu uzatır."
        case 8: return "Işık sürekli olarak tüm renkler arasında geçiş yapar."
        case 9: return "Işık renk değiştirerek yavaşça yanıp söner."
        default: return "Fare ışığı sabit olarak bu renkte yanar."
        }
    }
}

// MARK: - Ayarlar

struct SettingsPage: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        PageScroll {
            Card("Sensör", symbol: "scope") {
                SettingRow(title: "Kaldırma mesafesi (LOD)",
                           subtitle: "Fare yüzeyden kaldırıldığında imlecin durduğu yükseklik.") {
                    OptionPicker(title: "", value: $model.config.liftOff, options: Options.liftOff)
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
                Divider()
                SettingRow(title: "Dalgalanma kontrolü", subtitle: "DPI 9000 üzerindeyken oluşabilecek titremeyi azaltır.") {
                    Toggle("", isOn: $model.config.rippleControl).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Açı sabitleme", subtitle: "Çizgileri düzeltir; yatay ve dikey hareketleri düz tutar.") {
                    Toggle("", isOn: $model.config.angleSnap).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Hareket senkronizasyonu", subtitle: "Sensör okumasını rapor döngüsüyle eşitler, daha tutarlı hareket.") {
                    Toggle("", isOn: $model.config.motionSync).toggleStyle(.switch).labelsHidden()
                }
            }

            Card("Tuşlar ve tekerlek", symbol: "computermouse") {
                SettingRow(title: "Tuş gecikmesi (debounce)",
                           subtitle: "Düşük değer daha hızlı tepki verir; çift tıklama sorunu olursa artırın.") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { Double(model.config.debounce) },
                                              set: { model.config.debounce = Int($0.rounded()) }),
                               in: 0...20, step: 1)
                            .frame(width: 160)
                        Text("\(model.config.debounce) ms").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Divider()
                SettingRow(title: "Tekerlek yönü") {
                    OptionPicker(title: "", value: $model.config.scrollDirection, options: Options.scroll)
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }

            Card("Performans", symbol: "bolt") {
                SettingRow(title: "E-Spor modu", subtitle: "Fare performansını artırır, pil ömrünü kısaltır.") {
                    Toggle("", isOn: $model.config.eSports).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                SettingRow(title: "Hazırda bekleme süresi") {
                    OptionPicker(title: "", value: $model.config.sleepMinutes, options: Options.sleep)
                        .labelsHidden().frame(width: 160)
                }
            }
        }
    }
}

// MARK: - Günlük

struct LogPage: View {
    @EnvironmentObject var model: MouseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fareyle giden/gelen ham HID paketleri. Sorun bildirirken işe yarar.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
                }
                Button("Temizle") { model.logLines.removeAll() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .onChange(of: model.logLines.count) { _, n in
                    if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                }
            }
        }
        .padding(20)
    }
}
