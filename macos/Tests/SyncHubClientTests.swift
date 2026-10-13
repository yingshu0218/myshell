import Foundation
import XCTest
@testable import MyShell

final class SyncHubClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testChangesPreservesOpaqueCursorAndAuthorization() async throws {
        let session = makeSession()
        let client = try SyncHubClient(
            baseURL: URL(string: "https://sync.example.com")!,
            appID: "myshell",
            session: session
        )
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer secret"
            )
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(
                components?.queryItems?.first(where: { $0.name == "cursor" })?.value,
                "opaque+/= cursor"
            )
            let body = """
            {"changes":[],"cursor":"next-opaque"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, body)
        }

        let page = try await client.changes(
            cursor: "opaque+/= cursor",
            token: Data("secret".utf8)
        )
        XCTAssertEqual(page.cursor, "next-opaque")
    }

    func testClassifiesConflictWithoutExposingBody() async throws {
        let client = try SyncHubClient(
            baseURL: URL(string: "https://sync.example.com")!,
            appID: "myshell",
            session: makeSession()
        )
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 409,
                httpVersion: nil,
                headerFields: nil
            )!, Data("sensitive response".utf8))
        }

        do {
            _ = try await client.put(
                collection: "connections",
                recordID: UUID(),
                request: SyncWriteRequest(
                    baseVersion: 1,
                    payload: Data([1, 2, 3]),
                    checksum: "checksum"
                ),
                idempotencyKey: UUID(),
                token: Data("secret".utf8)
            )
            XCTFail("Expected conflict")
        } catch {
            XCTAssertEqual(error as? SyncHubError, .conflict)
            XCTAssertFalse(error.localizedDescription.contains("sensitive"))
        }
    }

    func testRejectsPlainHTTP() throws {
        XCTAssertThrowsError(
            try SyncHubClient(
                baseURL: URL(string: "http://sync.example.com")!,
                appID: "myshell"
            )
        ) { error in
            XCTAssertEqual(error as? SyncHubError, .invalidBaseURL)
        }
    }

    func testRejectsOversizedPayloadBeforeNetwork() async throws {
        let client = try SyncHubClient(
            baseURL: URL(string: "https://sync.example.com")!,
            appID: "myshell",
            session: makeSession()
        )
        MockURLProtocol.handler = { _ in
            XCTFail("Oversized payload must not reach the network")
            throw URLError(.badServerResponse)
        }

        do {
            _ = try await client.put(
                collection: "connections",
                recordID: UUID(),
                request: SyncWriteRequest(
                    baseVersion: 0,
                    payload: Data(
                        count: SyncHubClient.maximumPayloadBytes + 1
                    ),
                    checksum: "checksum"
                ),
                idempotencyKey: UUID(),
                token: Data("secret".utf8)
            )
            XCTFail("Expected payload limit error")
        } catch {
            XCTAssertEqual(error as? SyncHubError, .payloadTooLarge)
        }
    }

    func testRejectsOversizedResponseBeforeDecode() async throws {
        let client = try SyncHubClient(
            baseURL: URL(string: "https://sync.example.com")!,
            appID: "myshell",
            session: makeSession()
        )
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(count: SyncHubClient.maximumResponseBytes + 1)
            )
        }

        do {
            _ = try await client.changes(
                cursor: nil,
                token: Data("secret".utf8)
            )
            XCTFail("Expected response limit error")
        } catch {
            XCTAssertEqual(error as? SyncHubError, .responseTooLarge)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
