import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system:
            "Follow System"
        case .simplifiedChinese:
            "Simplified Chinese"
        case .english:
            "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        case .english:
            Locale(identifier: "en")
        }
    }
}

struct SettingsView: View {
    enum Presentation {
        case window
        case sidebar
    }

    let presentation: Presentation
    @AppStorage("followSystemAppearance") private var followsSystemAppearance = true
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("terminalTheme") private var terminalThemeRawValue = TerminalTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue

    init(presentation: Presentation = .window) {
        self.presentation = presentation
    }

    var body: some View {
        TabView {
            Form {
                Toggle("Follow system appearance", isOn: $followsSystemAppearance)
                Picker("Language", selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Picker("Theme", selection: $terminalThemeRawValue) {
                    ForEach(TerminalTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }

                LabeledContent("Font size") {
                    Stepper(
                        value: $terminalFontSize,
                        in: 10...28,
                        step: 1
                    ) {
                        Text("\(terminalFontSize, specifier: "%.0f") pt")
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
        }
        .frame(
            minWidth: presentation == .window ? 520 : 480,
            idealWidth: presentation == .window ? 520 : 720,
            minHeight: 300,
            idealHeight: presentation == .window ? 300 : 560
        )
        .frame(
            maxWidth: presentation == .sidebar ? .infinity : 520,
            maxHeight: presentation == .sidebar ? .infinity : 300
        )
        .scenePadding()
        .navigationTitle("Settings")
    }
}
