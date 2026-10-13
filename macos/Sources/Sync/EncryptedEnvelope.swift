import CryptoKit
import Foundation

struct EncryptedEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let algorithm: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

enum EnvelopeError: LocalizedError, Equatable {
    case invalidKey
    case invalidEnvelope
    case unsupportedEnvelope
    case checksumMismatch
    case authenticationFailed
    case invalidRecoveryKey
    case plaintextTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidKey: "The vault key is invalid."
        case .invalidEnvelope: "The encrypted record has an invalid format."
        case .unsupportedEnvelope: "The encrypted record version is unsupported."
        case .checksumMismatch: "The encrypted record checksum does not match."
        case .authenticationFailed: "The encrypted record could not be authenticated."
        case .invalidRecoveryKey: "The recovery key is invalid."
        case .plaintextTooLarge: "The decrypted record exceeds the allowed size."
        }
    }
}

enum EnvelopeCrypto {
    static let maximumPlaintextBytes = 786_432

    static func aad(
        appID: String,
        collection: String,
        recordID: UUID,
        schemaID: String
    ) -> Data {
        var result = Data("myshell-envelope-v1\0".utf8)
        for value in [appID, collection, recordID.uuidString.lowercased(), schemaID] {
            let bytes = Data(value.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(bytes)
        }
        return result
    }

    static func seal(
        plaintext: Data,
        key: Data,
        nonce: Data,
        aad: Data
    ) throws -> (payload: Data, checksum: String) {
        guard key.count == 32 else { throw EnvelopeError.invalidKey }
        guard nonce.count == 12 else { throw EnvelopeError.invalidEnvelope }
        guard plaintext.count <= maximumPlaintextBytes else {
            throw EnvelopeError.plaintextTooLarge
        }
        let cryptoNonce: AES.GCM.Nonce
        do {
            cryptoNonce = try AES.GCM.Nonce(data: nonce)
        } catch {
            throw EnvelopeError.invalidEnvelope
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: cryptoNonce,
            authenticating: aad
        )
        let envelope = EncryptedEnvelope(
            version: 1,
            algorithm: "A256GCM",
            nonce: nonce.base64URLEncodedString(),
            ciphertext: sealed.ciphertext.base64URLEncodedString(),
            tag: sealed.tag.base64URLEncodedString()
        )
        let payload = envelope.canonicalData
        return (payload, checksum(for: payload))
    }

    static func open(
        payload: Data,
        checksum expectedChecksum: String,
        key: Data,
        aad: Data
    ) throws -> Data {
        guard key.count == 32 else { throw EnvelopeError.invalidKey }
        guard checksum(for: payload) == expectedChecksum else {
            throw EnvelopeError.checksumMismatch
        }
        guard payload.count <= SyncHubClient.maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              Set(object.keys) == Set(["version", "algorithm", "nonce", "ciphertext", "tag"]),
              let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self, from: payload)
        else {
            throw EnvelopeError.invalidEnvelope
        }
        guard envelope.version == 1, envelope.algorithm == "A256GCM" else {
            throw EnvelopeError.unsupportedEnvelope
        }
        guard let nonce = Data(base64URL: envelope.nonce),
              let ciphertext = Data(base64URL: envelope.ciphertext),
              let tag = Data(base64URL: envelope.tag),
              nonce.count == 12,
              tag.count == 16
        else {
            throw EnvelopeError.invalidEnvelope
        }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext = try AES.GCM.open(
                box,
                using: SymmetricKey(data: key),
                authenticating: aad
            )
            guard plaintext.count <= maximumPlaintextBytes else {
                throw EnvelopeError.plaintextTooLarge
            }
            return plaintext
        } catch let error as EnvelopeError {
            throw error
        } catch {
            throw EnvelopeError.authenticationFailed
        }
    }

    static func recoveryKey(for key: Data) throws -> String {
        guard key.count == 32 else { throw EnvelopeError.invalidKey }
        let digest = recoveryChecksum(key)
        return "myshell-v1-\(key.base64URLEncodedString())-\(digest)"
    }

    static func key(fromRecoveryKey value: String) throws -> Data {
        let prefix = "myshell-v1-"
        guard value.hasPrefix(prefix), value.count == prefix.count + 43 + 1 + 8 else {
            throw EnvelopeError.invalidRecoveryKey
        }
        let remainder = value.dropFirst(prefix.count)
        let separator = remainder.index(remainder.endIndex, offsetBy: -9)
        guard remainder[separator] == "-" else {
            throw EnvelopeError.invalidRecoveryKey
        }
        let encoded = String(remainder[..<separator])
        let suppliedChecksum = String(remainder[remainder.index(after: separator)...])
        guard let key = Data(base64URL: encoded),
              key.count == 32,
              suppliedChecksum == recoveryChecksum(key)
        else {
            throw EnvelopeError.invalidRecoveryKey
        }
        return key
    }

    static func checksum(for payload: Data) -> String {
        "sha256:" + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func recoveryChecksum(_ key: Data) -> String {
        var material = Data("myshell-recovery-v1\0".utf8)
        material.append(key)
        return SHA256.hash(data: material).prefix(4)
            .map { String(format: "%02x", $0) }.joined()
    }
}

private extension EncryptedEnvelope {
    var canonicalData: Data {
        Data(
            """
            {"version":\(version),"algorithm":"\(algorithm)","nonce":"\(nonce)","ciphertext":"\(ciphertext)","tag":"\(tag)"}
            """.utf8
        )
    }
}

private extension Data {
    init?(base64URL value: String) {
        guard !value.contains("="),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: "-_"))
                      .contains($0)
              })
        else {
            return nil
        }
        var standard = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        self.init(base64Encoded: standard)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
