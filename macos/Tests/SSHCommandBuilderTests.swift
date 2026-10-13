import XCTest
@testable import MyShell

final class SSHCommandBuilderTests: XCTestCase {
    func testBuildsSystemSSHArgumentsWithoutSecrets() throws {
        let draft = SSHConnectionDraft(
            name: "Production",
            host: "server.example.com",
            user: "deploy",
            port: 2202,
            identityFile: "~/.ssh/id_ed25519",
            proxyJump: "jump@example.net"
        )

        let configuration = try SSHCommandBuilder.configuration(for: draft)

        XCTAssertEqual(configuration.executable, "/usr/bin/ssh")
        XCTAssertEqual(
            configuration.arguments.suffix(7),
            [
                "-p", "2202",
                "-i", NSString(string: "~/.ssh/id_ed25519").expandingTildeInPath,
                "-J", "jump@example.net",
                "deploy@server.example.com",
            ]
        )
        XCTAssertFalse(configuration.arguments.joined().contains("password"))
    }

    func testUsesSSHConfigAndAgentDefaultsWhenOptionalFieldsAreEmpty() throws {
        let configuration = try SSHCommandBuilder.configuration(
            for: SSHConnectionDraft(host: "host-alias")
        )

        XCTAssertEqual(configuration.arguments.last, "host-alias")
        XCTAssertFalse(configuration.arguments.contains("-i"))
        XCTAssertFalse(configuration.arguments.contains("-J"))
    }

    func testRejectsOptionInjectionAndInvalidPort() {
        XCTAssertThrowsError(
            try SSHCommandBuilder.configuration(
                for: SSHConnectionDraft(host: "-oProxyCommand=bad")
            )
        ) { error in
            XCTAssertEqual(error as? SSHConfigurationError, .invalidHost)
        }

        XCTAssertThrowsError(
            try SSHCommandBuilder.configuration(
                for: SSHConnectionDraft(host: "example.com", port: 0)
            )
        ) { error in
            XCTAssertEqual(error as? SSHConfigurationError, .invalidPort)
        }
    }
}
