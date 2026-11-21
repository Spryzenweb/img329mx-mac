import SwiftUI

struct PageScroll<Content: View>: View {
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, symbol: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        if let symbol {
                            Label(title, systemImage: symbol).font(.headline)
                        } else {
                            Text(title).font(.headline)
                        }
                    }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

struct MouseImage: View {
    var body: some View {
        if let img = Bundle.main.image(forResource: "mouse") {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "computermouse.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

/// Farenin resmi, arkasında seçili ışık renginde bir parıltı ile.
struct GlowingMouse: View {
    let mode: Int
    var height: CGFloat = 220

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !(mode == 8 || mode == 9))) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let (color, strength) = glow(t)
            ZStack {
                Ellipse()
                    .fill(color.opacity(0.75 * strength))
                    .frame(width: height * 0.55, height: height * 0.85)
                    .blur(radius: height * 0.16)
                MouseImage().frame(height: height)
            }
            .frame(width: height * 0.9, height: height * 1.05)
        }
    }

    private func glow(_ t: Double) -> (Color, Double) {
        switch mode {
        case 0: return (.clear, 0)
        case 8: return (Color(hue: (t / 6).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1), 1)
        case 9:
            let hue = (t / 24).truncatingRemainder(dividingBy: 1)
            let s = 0.15 + 0.85 * (0.5 + 0.5 * sin(t * 2 * .pi / 3))
            return (Color(hue: hue, saturation: 0.9, brightness: 1), s)
        default:
            return (Lighting.modes.first(where: { $0.id == mode })?.color ?? .clear, 1)
        }
    }
}

/// Işık modu için küçük renk dairesi
struct LightDot: View {
    let mode: Int
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch mode {
            case 0:
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
                    .overlay(Rectangle().fill(Color.secondary).frame(width: 1.5).rotationEffect(.degrees(45)))
                    .clipShape(Circle())
            case 8:
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
            case 9:
                Circle().fill(RadialGradient(colors: [.white, .pink, .purple.opacity(0.4)], center: .center,
                                             startRadius: 0, endRadius: size * 0.6))
            default:
                Circle().fill(Lighting.modes.first(where: { $0.id == mode })?.color ?? .gray)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Cihazdan bilinmeyen bir değer gelirse onu da listede gösterir, böylece istemeden değişmez.
struct OptionPicker: View {
    let title: String
    @Binding var value: Int
    let options: [(Int, String)]

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(allOptions, id: \.0) { opt in
                Text(opt.1).tag(opt.0)
            }
        }
    }

    private var allOptions: [(Int, String)] {
        options.contains(where: { $0.0 == value }) ? options : options + [(value, "Bilinmiyor (\(value))")]
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: String
    var tint: Color = .accentColor
    var accessory: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }
}
