import AppKit
@preconcurrency import SwiftTerm
import SwiftUI
import QuartzCore

struct TerminalSurface: NSViewRepresentable {
    let session: TerminalSessionModel
    let theme: TerminalTheme
    let fontSize: CGFloat
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminalView = TerminalView(
            frame: .zero,
            font: NSFont.monospacedSystemFont(
                ofSize: fontSize,
                weight: .regular
            )
        )
        terminalView.terminalDelegate = context.coordinator
        terminalView.changeScrollback(10_000)
        context.coordinator.attach(to: terminalView)
        applyAppearance(to: terminalView)
        context.coordinator.appliedTheme = theme
        context.coordinator.appliedFontSize = fontSize

        DispatchQueue.main.async {
            if isActive {
                terminalView.window?.makeFirstResponder(terminalView)
            }
            let environment = ProcessInfo.processInfo.environment
            if environment["MYSHELL_PERFORMANCE_MODE"] == "1",
               environment["MYSHELL_PERFORMANCE_METAL"] == "1" {
                try? terminalView.setUseMetal(true)
            }
        }
        return terminalView
    }

    func updateNSView(_ terminalView: TerminalView, context: Context) {
        context.coordinator.session = session
        if context.coordinator.appliedTheme != theme
            || context.coordinator.appliedFontSize != fontSize {
            applyAppearance(to: terminalView)
            context.coordinator.appliedTheme = theme
            context.coordinator.appliedFontSize = fontSize
        }
        if isActive, !context.coordinator.wasActive {
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
        context.coordinator.wasActive = isActive
    }

    static func dismantleNSView(
        _ terminalView: TerminalView,
        coordinator: Coordinator
    ) {
        terminalView.terminalDelegate = nil
        coordinator.detach()
    }

    private func applyAppearance(to terminalView: TerminalView) {
        let resolvedFontSize = min(max(fontSize, 10), 28)
        if abs(terminalView.font.pointSize - resolvedFontSize) > 0.1 {
            terminalView.font = NSFont.monospacedSystemFont(
                ofSize: resolvedFontSize,
                weight: .regular
            )
        }
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.nativeBackgroundColor = theme.backgroundColor
        terminalView.caretColor = theme.cursorColor
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        var session: TerminalSessionModel
        var wasActive = false
        var appliedTheme: TerminalTheme?
        var appliedFontSize: CGFloat?
        private let consumerID = UUID()
        private weak var terminalView: TerminalView?

        init(session: TerminalSessionModel) {
            self.session = session
        }

        func attach(to terminalView: TerminalView) {
            self.terminalView = terminalView
            session.attachOutputConsumer(id: consumerID) { [weak terminalView] data in
                guard let terminalView else {
                    return
                }
                PerformanceLatencyProbe.shared.markOutputReceived()
                let measuresLatency = PerformanceLatencyProbe.shared.isEnabled
                if measuresLatency {
                    CATransaction.begin()
                    CATransaction.setCompletionBlock {
                        DispatchQueue.main.async {
                            PerformanceLatencyProbe.shared
                                .markDisplayCommitCompleted()
                        }
                    }
                }
                let bytes = [UInt8](data)
                terminalView.feed(byteArray: bytes[...])
                PerformanceLatencyProbe.shared.markFeedCompleted()
                if measuresLatency {
                    CATransaction.commit()
                }
            }
        }

        func detach() {
            session.detachOutputConsumer(id: consumerID)
            terminalView = nil
        }

        func sizeChanged(
            source: TerminalView,
            newCols: Int,
            newRows: Int
        ) {
            PerformanceResizeProbe.shared.recordTerminalResize()
            session.resize(columns: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            if PerformanceTUIProbe.shared
                .consumeCompletionTitleIfExpected(title) {
                return
            }
            session.updateTitle(title)
        }

        func hostCurrentDirectoryUpdate(
            source: TerminalView,
            directory: String?
        ) {
            session.updateCurrentDirectory(directory)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session.send(data)
        }

        func scrolled(source: TerminalView, position: Double) {}

        func rangeChanged(
            source: TerminalView,
            startY: Int,
            endY: Int
        ) {}

        func requestOpenLink(
            source: TerminalView,
            link: String,
            params: [String: String]
        ) {
            guard let url = URL(string: link),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
