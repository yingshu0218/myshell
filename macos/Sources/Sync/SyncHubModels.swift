import Foundation

struct SyncRecordEnvelope: Codable, Equatable, Sendable {
    let appID: String
    let collection: String
    let recordID: String
    let baseVersion: Int64?
    let version: Int64
    let deleted: Bool
    let updatedAt: Date
    let payload: Data?
    let checksum: String?

    enum CodingKeys: String, CodingKey {
        case appID = "appId"
        case collection
        case recordID = "recordId"
        case baseVersion
        case version
        case deleted
        case updatedAt
        case payload
        case checksum
    }
}

struct SyncChangesPage: Codable, Equatable, Sendable {
    let changes: [SyncRecordEnvelope]
    let cursor: String
}

struct SyncWriteRequest: Codable, Equatable, Sendable {
    let baseVersion: Int64
    let payload: Data
    let checksum: String
}

struct SyncDeleteRequest: Codable, Equatable, Sendable {
    let baseVersion: Int64
}

struct SyncHubErrorBody: Codable, Equatable, Sendable {
    let code: String?
    let message: String?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestID = "requestId"
    }
}

enum SyncHubError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidIdentifier
    case missingToken
    case invalidResponse
    case responseTooLarge
    case unauthorized
    case forbidden
    case conflict
    case payloadTooLarge
    case invalidRequest
    case server(status: Int)
    case transport

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Sync Hub must use HTTPS (localhost may use HTTP)."
        case .invalidIdentifier: "A Sync Hub identifier is invalid."
        case .missingToken: "The Sync Hub token is missing."
        case .invalidResponse: "Sync Hub returned an invalid response."
        case .responseTooLarge: "Sync Hub returned more data than allowed."
        case .unauthorized: "The Sync Hub token is invalid or revoked."
        case .forbidden: "The token cannot access this application."
        case .conflict: "This record changed on another device."
        case .payloadTooLarge: "The encrypted record exceeds the 1 MiB limit."
        case .invalidRequest: "Sync Hub rejected the request."
        case .server: "Sync Hub is temporarily unavailable."
        case .transport: "Unable to reach Sync Hub."
        }
    }
}
