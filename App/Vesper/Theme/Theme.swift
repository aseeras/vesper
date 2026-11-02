import SwiftUI

/// Grand-tourer-meets-secret-service palette. An homage, not a brand.
enum Theme {
    static let racingGreen = Color(red: 0.0, green: 0.26, blue: 0.15)      // #004225
    static let deepGreen = Color(red: 0.03, green: 0.11, blue: 0.08)       // #081C14
    static let tuxedo = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let silver = Color(red: 0.78, green: 0.80, blue: 0.82)
    static let gold = Color(red: 0.79, green: 0.66, blue: 0.29)            // #C9A94B
    static let signalRed = Color(red: 0.72, green: 0.08, blue: 0.10)

    static let background = LinearGradient(colors: [deepGreen, tuxedo], startPoint: .top, endPoint: .bottom)

    /// Didot reads as tailored and expensive; Menlo for anything that is a number.
    static func title(_ size: CGFloat) -> Font { .custom("Didot", size: size).weight(.bold) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default).width(.expanded) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

/// Letter-spaced small caps, the "CLASSIFIED" look.
struct Tracked: ViewModifier {
    var size: CGFloat = 11
    var color: Color = Theme.silver
    func body(content: Content) -> some View {
        content.font(Theme.label(size)).tracking(size * 0.35).foregroundStyle(color).textCase(.uppercase)
    }
}

extension View {
    func tracked(_ size: CGFloat = 11, _ color: Color = Theme.silver) -> some View { modifier(Tracked(size: size, color: color)) }
}

/// Brushed-metal button with a gold hairline.
struct GoldButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tracked(13, prominent ? Theme.tuxedo : Theme.gold)
            .padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(prominent
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.75), Theme.gold],
                                                        startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.clear))
            )
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.gold, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A manila-folder-style card for a mission in the dossier.
struct DossierCard<Content: View>: View {
    var stamp: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.racingGreen.opacity(0.35))
            .overlay(Rectangle().stroke(Theme.gold.opacity(0.4), lineWidth: 0.5))
            .overlay(alignment: .topTrailing) {
                if let stamp {
                    Text(stamp).tracked(9, Theme.signalRed)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Theme.signalRed, lineWidth: 1))
                        .rotationEffect(.degrees(-8)).padding(10)
                }
            }
    }
}

/// Thin gold rule with a label in the middle.
struct SectionRule: View {
    var title: String
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.gold.opacity(0.5)).frame(height: 0.5)
            Text(title).tracked(10, Theme.gold)
            Rectangle().fill(Theme.gold.opacity(0.5)).frame(height: 0.5)
        }
    }
}
