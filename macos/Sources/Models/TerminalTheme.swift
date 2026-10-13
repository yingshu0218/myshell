import AppKit
import Foundation
import SwiftUI

enum TerminalTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case midnight
    case solarizedDark
    case paper
    case highContrast

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .midnight: "Midnight"
        case .solarizedDark: "Solarized Dark"
        case .paper: "Paper"
        case .highContrast: "High Contrast"
        }
    }

    @MainActor
    var foregroundColor: NSColor {
        switch self {
        case .system: .textColor
        case .midnight: NSColor(srgbRed: 0.78, green: 0.84, blue: 0.91, alpha: 1)
        case .solarizedDark: NSColor(srgbRed: 0.51, green: 0.58, blue: 0.59, alpha: 1)
        case .paper: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1)
        case .highContrast: .white
        }
    }

    @MainActor
    var backgroundColor: NSColor {
        switch self {
        case .system: .textBackgroundColor
        case .midnight: NSColor(srgbRed: 0.035, green: 0.055, blue: 0.09, alpha: 1)
        case .solarizedDark: NSColor(srgbRed: 0.0, green: 0.17, blue: 0.21, alpha: 1)
        case .paper: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        case .highContrast: .black
        }
    }

    @MainActor
    var cursorColor: NSColor {
        switch self {
        case .system: .controlAccentColor
        case .midnight: NSColor(srgbRed: 0.36, green: 0.72, blue: 1, alpha: 1)
        case .solarizedDark: NSColor(srgbRed: 0.71, green: 0.54, blue: 0, alpha: 1)
        case .paper: NSColor(srgbRed: 0.72, green: 0.22, blue: 0.16, alpha: 1)
        case .highContrast: .systemYellow
        }
    }
}
