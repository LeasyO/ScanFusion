import SwiftUI
import UIKit

/// Identidade visual: preto profundo + dourado, tipografia serifada no estilo estúdio.
/// Para trocar a paleta, edite só as cores abaixo.
enum Theme {
    static let ink = Color(red: 0.043, green: 0.043, blue: 0.047)          // #0B0B0C
    static let surface = Color(red: 0.086, green: 0.082, blue: 0.090)      // #161517
    static let surfaceHigh = Color(red: 0.133, green: 0.125, blue: 0.133)  // #222022
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)         // #C9A24A
    static let goldLight = Color(red: 0.902, green: 0.780, blue: 0.478)    // #E6C77A
    static let goldDeep = Color(red: 0.545, green: 0.420, blue: 0.157)     // #8B6B28
    static let ivory = Color(red: 0.949, green: 0.929, blue: 0.894)        // #F2EDE4
    static let muted = Color(red: 0.620, green: 0.600, blue: 0.570)        // #9E9991
    static let danger = Color(red: 0.850, green: 0.350, blue: 0.300)

    static let goldGradient = LinearGradient(
        colors: [goldLight, gold, goldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }

    static var uiGold: UIColor { UIColor(gold) }

    static func applyUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(ink)
        nav.shadowColor = UIColor(gold.opacity(0.15))
        let serif = UIFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.serif)
        let serifLarge = UIFont.systemFont(ofSize: 32, weight: .semibold).fontDescriptor.withDesign(.serif)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(ivory),
            .font: serif.map { UIFont(descriptor: $0, size: 17) } ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(goldLight),
            .font: serifLarge.map { UIFont(descriptor: $0, size: 32) } ?? UIFont.systemFont(ofSize: 32, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

struct GoldButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(filled ? Theme.ink : Theme.goldLight)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.goldGradient)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.ink.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.gold.opacity(0.55), lineWidth: 1)
                        )
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.18), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    func studioBackground() -> some View {
        background(Theme.ink.ignoresSafeArea())
    }
}

struct OrnamentDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.gold.opacity(0.35)).frame(height: 0.5)
            Image(systemName: "diamond.fill")
                .font(.system(size: 6))
                .foregroundStyle(Theme.gold)
            Rectangle().fill(Theme.gold.opacity(0.35)).frame(height: 0.5)
        }
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
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.ivory)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.5))
    }
}

/// Botão redondo de fechar para telas cheias.
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.goldLight)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 0.5))
        }
        .accessibilityLabel("Fechar")
    }
}
