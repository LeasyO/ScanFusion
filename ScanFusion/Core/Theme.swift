import SwiftUI
import UIKit

/// Identidade visual: grafite profundo + champanhe, no estilo de instrumento de precisão.
/// Para trocar a paleta, edite só as cores abaixo.
enum Theme {
    static let ink = Color(red: 0.027, green: 0.031, blue: 0.039)          // #07080A
    static let surface = Color(red: 0.075, green: 0.078, blue: 0.090)      // #131417
    static let surfaceHigh = Color(red: 0.118, green: 0.122, blue: 0.137)  // #1E1F23
    static let gold = Color(red: 0.831, green: 0.698, blue: 0.416)         // #D4B26A
    static let goldLight = Color(red: 0.945, green: 0.851, blue: 0.627)    // #F1D9A0
    static let goldDeep = Color(red: 0.612, green: 0.478, blue: 0.208)     // #9C7A35
    static let ivory = Color(red: 0.957, green: 0.945, blue: 0.918)        // #F4F1EA
    static let muted = Color(red: 0.557, green: 0.541, blue: 0.518)        // #8E8A84
    static let hairline = Color.white.opacity(0.08)
    static let danger = Color(red: 0.937, green: 0.408, blue: 0.361)

    static let goldGradient = LinearGradient(
        colors: [goldLight, gold, goldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Borda fina que acende no canto superior, como luz batendo no vidro.
    static let rimGradient = LinearGradient(
        colors: [gold.opacity(0.55), Color.white.opacity(0.06), Color.white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static var uiGold: UIColor { UIColor(gold) }

    static func applyUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        nav.backgroundColor = UIColor(ink.opacity(0.6))
        nav.shadowColor = UIColor(white: 1, alpha: 0.06)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(ivory),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(ivory),
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(gold)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(gold)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(ink)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(ivory)], for: .normal)
    }
}

struct GoldButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Theme.ink : Theme.ivory)
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background {
                if filled {
                    shape.fill(Theme.goldGradient)
                        .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: Theme.gold.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 14, y: 6)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(Theme.surface.opacity(0.55)))
                        .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return content
            .padding(16)
            .background(
                shape.fill(
                    LinearGradient(colors: [Theme.surfaceHigh, Theme.surface],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    func studioBackground() -> some View {
        background(StudioBackdrop().ignoresSafeArea())
    }
}

/// Fundo grafite com brilho champanhe no topo e grade de pontos que lembra a nuvem do LiDAR.
struct StudioBackdrop: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(
                colors: [Theme.gold.opacity(0.16), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            Canvas { context, size in
                let step: CGFloat = 22
                let limit = size.height * 0.55
                var y: CGFloat = step / 2
                while y < limit {
                    let fade = 1 - y / limit
                    var x: CGFloat = step / 2
                    while x < size.width {
                        let dot = CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.07 * fade)))
                        x += step
                    }
                    y += step
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Selo do app: mira de scanner dentro de um círculo champanhe.
struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Theme.goldGradient)
            Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            Image(systemName: "viewfinder")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.gold.opacity(0.4), radius: 12, y: 4)
        .accessibilityHidden(true)
    }
}

/// Ícone de modo: quadrado de vidro com brilho dourado.
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 52
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        return ZStack {
            shape.fill(Theme.ink.opacity(0.7))
            shape.fill(RadialGradient(colors: [Theme.gold.opacity(0.28), .clear],
                                      center: .topLeading, startRadius: 0, endRadius: size))
            shape.strokeBorder(Theme.rimGradient, lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(Theme.goldGradient)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct OrnamentDivider: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.gold.opacity(0.5), Theme.hairline, .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow())
            .tracking(2)
            .foregroundStyle(Theme.gold)
    }
}

/// Pílula translúcida usada sobre a câmera.
struct HUDPill: View {
    let text: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).foregroundStyle(Theme.gold)
            }
            Text(text).monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.ivory)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.rimGradient, lineWidth: 0.75))
        .environment(\.colorScheme, .dark)
    }
}

/// "i" dourado: toque para ver, num balão, como usar a ferramenta ao lado.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Como usar")
        .popover(isPresented: $shown) {
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.ivory)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.surfaceHigh)
        }
    }
}

/// Botão redondo de fechar para telas cheias.
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ivory)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.rimGradient, lineWidth: 0.75))
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel("Fechar")
    }
}
