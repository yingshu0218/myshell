import Foundation

enum SanitizedEnvironment {
    private static let sensitiveFragments = [
        "TOKEN",
        "PASSWORD",
        "PASSWD",
        "SECRET",
        "API_KEY",
        "PRIVATE_KEY",
        "AUTHORIZATION",
        "CREDENTIAL",
    ]

    static func terminal(
        from source: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        source.filter { key, _ in
            let normalized = key.uppercased()
            return !sensitiveFragments.contains {
                normalized.contains($0)
            }
        }
    }
}
