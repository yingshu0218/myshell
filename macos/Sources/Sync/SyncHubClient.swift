import Foundation

struct SyncHubClient: Sendable {
    static let maximumPayloadBytes = 1_048_576
    static let maximumResponseBytes = 2_097_152

    let baseURL: URL
    let appID: String
    let session: URLSession

    init(
        baseURL: URL,
        appID: String,
        session: URLSession = .shared
    ) throws {
        guard Self.isAllowedBaseURL(baseURL) else {
            throw SyncHubError.invalidBaseURL
        }
        guard Self.isValidIdentifier(appID) else {
            throw SyncHubError.invalidIdentifier
        }
        self.baseURL = baseURL
        self.appID = appID
        self.session = session
    }

    func changes(
        cursor: String?,
        limit: Int = 32,
        token: Data
    ) async throws -> SyncChangesPage {
        guard (1...32).contains(limit) else {
            throw SyncHubError.invalidRequest
        }
        var components = URLComponents(
            url: endpoint(["v1", "apps", appID, "changes"]),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SyncHubError.invalidBaseURL
        }
        let request = try authorizedRequest(url: url, method: "GET", token: token)
        return try await send(request, as: SyncChangesPage.self)
    }

    func put(
        collection: String,
        recordID: UUID,
        request body: SyncWriteRequest,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        guard Self.isValidIdentifier(collection),
              body.payload.count <= Self.maximumPayloadBytes else {
            throw body.payload.count > Self.maximumPayloadBytes
                ? SyncHubError.payloadTooLarge
                : SyncHubError.invalidIdentifier
        }
        let url = recordURL(collection: collection, recordID: recordID)
        var request = try authorizedRequest(url: url, method: "PUT", token: token)
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(body)
        return try await send(request, as: SyncRecordEnvelope.self)
    }

    func get(
        collection: String,
        recordID: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        guard Self.isValidIdentifier(collection) else {
            throw SyncHubError.invalidIdentifier
        }
        let request = try authorizedRequest(
            url: recordURL(collection: collection, recordID: recordID),
            method: "GET",
            token: token
        )
        return try await send(request, as: SyncRecordEnvelope.self)
    }

    func delete(
        collection: String,
        recordID: UUID,
        baseVersion: Int64,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        guard Self.isValidIdentifier(collection) else {
            throw SyncHubError.invalidIdentifier
        }
        let url = recordURL(collection: collection, recordID: recordID)
        var request = try authorizedRequest(url: url, method: "DELETE", token: token)
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(
            SyncDeleteRequest(baseVersion: baseVersion)
        )
        return try await send(request, as: SyncRecordEnvelope.self)
    }

    private func authorizedRequest(
        url: URL,
        method: String,
        token: Data
    ) throws -> URLRequest {
        guard !token.isEmpty, let tokenString = String(data: token, encoding: .utf8) else {
            throw SyncHubError.missingToken
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(tokenString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable & Sendable>(
        _ request: URLRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncHubError.transport
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncHubError.invalidResponse
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw SyncHubError.responseTooLarge
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.classify(status: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SyncHubError.invalidResponse
        }
    }

    private func recordURL(collection: String, recordID: UUID) -> URL {
        endpoint([
            "v1", "apps", appID, "collections", collection,
            "records", recordID.uuidString,
        ])
    }

    private func endpoint(_ components: [String]) -> URL {
        components.reduce(baseURL) { partial, component in
            partial.appending(path: component)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func classify(status: Int) -> SyncHubError {
        switch status {
        case 400, 422: .invalidRequest
        case 401: .unauthorized
        case 403: .forbidden
        case 409: .conflict
        case 413: .payloadTooLarge
        case 500...599: .server(status: status)
        default: .invalidResponse
        }
    }

    private static func isAllowedBaseURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" {
            return url.host != nil
        }
        return url.scheme?.lowercased() == "http"
            && ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }
}
