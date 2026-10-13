import Foundation

enum ApplicationPaths {
    static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(
            path: "com.yingshu0218.myshell",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory
    }

    static func databaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "myshell.sqlite3")
    }
}
