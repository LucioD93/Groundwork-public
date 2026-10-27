import SwiftUI
import UIKit

enum JournalAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Terracotta & Cocoa: warm porcelain and clay by day, roasted cocoa by night.
/// Dynamic UIColors also update native navigation chrome and presented sheets.
enum JournalTheme {
    static let background = Color(uiColor: backgroundUI)
    static let chrome = Color(uiColor: chromeUI)
    static let surface = Color(uiColor: surfaceUI)
    static let text = Color(uiColor: textUI)
    static let secondaryText = Color(uiColor: secondaryTextUI)
    static let accent = Color(uiColor: accentUI)
    static let danger = Color(uiColor: adaptive(light: 0xA52E36, dark: 0xF1A4A4))
    static let rating = Color(uiColor: accentUI)
    static let unselectedRating = Color(uiColor: adaptive(light: 0x967D70, dark: 0x9E7A6A))
    static let photoBackground = Color(uiColor: adaptive(light: 0xEAD9CC, dark: 0x49332B))
    static let separator = Color(uiColor: separatorUI)

    // Porcelain cards sit above a warm canvas; dark cards lift out of cocoa.
    private static let backgroundUI = adaptive(light: 0xFAF0E8, dark: 0x211715)
    private static let chromeUI = adaptive(light: 0xFFF9F3, dark: 0x211715)
    private static let surfaceUI = adaptive(light: 0xFFF9F3, dark: 0x342520)
    private static let textUI = adaptive(light: 0x3D2924, dark: 0xF8E8DD)
    private static let secondaryTextUI = adaptive(light: 0x795D52, dark: 0xD0AFA0)
    private static let accentUI = adaptive(light: 0x9E4E35, dark: 0xE6A18A)
    private static let separatorUI = adaptive(light: 0xDECABE, dark: 0x5A4035)

    private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    @MainActor static func configureNavigation() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = chromeUI
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: textUI]
        navigation.largeTitleTextAttributes = [.foregroundColor: textUI]
        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigation
        navigationBar.scrollEdgeAppearance = navigation
        navigationBar.compactAppearance = navigation
        navigationBar.compactScrollEdgeAppearance = navigation
        navigationBar.tintColor = accentUI

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = chromeUI
        tabs.shadowColor = separatorUI
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = secondaryTextUI
            item.normal.titleTextAttributes = [.foregroundColor: secondaryTextUI]
            item.selected.iconColor = accentUI
            item.selected.titleTextAttributes = [.foregroundColor: accentUI]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = accentUI
        UITabBar.appearance().unselectedItemTintColor = secondaryTextUI
    }
}

/// Apply row surfaces to the content, since List/Form ignore listRowBackground
/// when it is attached to the scrolling container itself.
struct JournalList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            content
                .listRowBackground(JournalTheme.surface)
                .listRowSeparatorTint(JournalTheme.separator)
        }.journalStyle()
    }
}

struct JournalForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
                .listRowBackground(JournalTheme.surface)
                .listRowSeparatorTint(JournalTheme.separator)
        }.journalStyle()
    }
}

extension View {
    func journalStyle() -> some View {
        modifier(JournalStyle())
    }

    func journalTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(JournalTheme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }

    func journalAction(destructive: Bool = false, fixedLabel: Bool = false) -> some View {
        buttonStyle(JournalActionStyle(destructive: destructive, fixedLabel: fixedLabel))
    }
}

private struct JournalStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(JournalTheme.text)
            .tint(JournalTheme.accent)
            .scrollContentBackground(.hidden)
            .background(JournalTheme.background)
            .toolbarBackground(JournalTheme.chrome, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
    }
}

private struct JournalActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var destructive: Bool
    var fixedLabel: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: fixedLabel, vertical: false)
            .foregroundStyle(destructive || configuration.role == .destructive ? JournalTheme.danger : JournalTheme.accent)
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
    }
}

extension View {
    func journalPrimary() -> some View {
        buttonStyle(JournalPrimaryStyle())
    }
}

private struct JournalPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .foregroundStyle(JournalTheme.surface)
            .background(JournalTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct InlineError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(JournalTheme.danger)
            .accessibilityLabel("Needs attention: " + message)
    }
}
