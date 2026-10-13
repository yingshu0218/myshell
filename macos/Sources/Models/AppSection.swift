import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case localShell
    case connections
    case commandGroups
    case sync
    case settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .localShell:
            "Local Shell"
        case .connections:
            "Connections"
        case .commandGroups:
            "Quick Commands"
        case .sync:
            "Sync"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .localShell:
            "terminal"
        case .connections:
            "network"
        case .commandGroups:
            "text.badge.plus"
        case .sync:
            "arrow.triangle.2.circlepath"
        case .settings:
            "gearshape"
        }
    }
}
