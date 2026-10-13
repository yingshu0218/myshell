import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ConnectionArchivePanel {
    static func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "myshell-connections.json"
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
