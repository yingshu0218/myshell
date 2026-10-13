import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection?
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if !isCollapsed {
                    Text("MyShell")
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "sidebar.left")
                        .font(
                            .system(
                                size: isCollapsed ? 14 : 13,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(isCollapsed ? .white : .secondary)
                        .frame(
                            width: isCollapsed ? 36 : 24,
                            height: isCollapsed ? 34 : 24
                        )
                        .background(
                            isCollapsed
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
                .accessibilityLabel(
                    isCollapsed ? "Expand Sidebar" : "Collapse Sidebar"
                )
            }
            .padding(.horizontal, isCollapsed ? 8 : 12)
            .frame(height: 36)

            if isCollapsed {
                Divider()
                    .padding(.horizontal, 8)
            }

            if isCollapsed {
                collapsedNavigation
            } else {
                expandedNavigation
            }
        }
        .padding(.top, 4)
        .frame(width: isCollapsed ? 52 : 176)
        .background(.bar)
        .animation(.easeInOut(duration: 0.16), value: isCollapsed)
    }

    private var expandedNavigation: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var collapsedNavigation: some View {
        VStack(spacing: 6) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 34)
                        .foregroundStyle(
                            selection == section ? .primary : .secondary
                        )
                        .background(
                            selection == section
                                ? AnyShapeStyle(.quaternary)
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(
                    selection == section ? .isSelected : []
                )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
