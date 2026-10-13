import SwiftUI

struct DetailPlaceholderView: View {
    let section: AppSection?

    var body: some View {
        ContentUnavailableView {
            Label(
                section?.title ?? "MyShell",
                systemImage: section?.systemImage ?? "terminal"
            )
        } description: {
            Text(description)
        }
    }

    private var description: LocalizedStringKey {
        switch section {
        case .localShell:
            "Open a local terminal with Command-T."
        case .connections:
            "Saved SSH connections arrive in M5."
        case .commandGroups:
            "Save and run reusable command groups."
        case .sync:
            "Encrypted Sync Hub integration arrives in M6."
        case .settings:
            "Configure MyShell preferences."
        case nil:
            "Choose a destination from the sidebar."
        }
    }
}
