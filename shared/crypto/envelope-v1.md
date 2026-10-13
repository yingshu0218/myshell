# Encrypted Envelope v1

## Scope and primitives

Each business record is independently encrypted with AES-256-GCM. The vault key is exactly
32 random bytes. Every encryption uses a fresh, cryptographically random 12-byte nonce; a
client must never reuse a nonce with the same key. Decrypted plaintext is UTF-8 JSON and is
limited to 768 KiB before schema validation.

The Sync Hub `payload` is standard padded Base64 of the exact UTF-8 bytes of this compact JSON:

```json
{"version":1,"algorithm":"A256GCM","nonce":"<base64url>","ciphertext":"<base64url>","tag":"<base64url>"}
```

Envelope binary fields use RFC 4648 Base64url without padding. `nonce` decodes to 12 bytes and
`tag` to 16 bytes. Field order has no meaning when reading. Writers use the displayed order and
no optional whitespace so checksum results are reproducible. Unknown fields, versions, or
algorithms are rejected before decryption.

## Authenticated data

AAD is the following byte sequence:

1. ASCII `myshell-envelope-v1` followed by one zero byte.
2. In order: app ID, collection, lowercase record UUID, schema ID.
3. Each value is UTF-8 prefixed by its unsigned 32-bit big-endian byte length.

The schema IDs are `connection-v1`, `group-v1`, `terminal-profile-v1`, and
`command-group-v1`. Changing any bound value must make authentication fail.

## Checksum

The Sync Hub checksum is `sha256:` followed by lowercase hexadecimal SHA-256 of the exact
envelope UTF-8 bytes. It detects transport/storage mistakes; AES-GCM remains the security
integrity check. A checksum mismatch is rejected before parsing the envelope.

## Recovery key

The portable representation of the 32-byte vault key is:

```text
myshell-v1-<unpadded-base64url-key>-<eight-lowercase-hex-check-digits>
```

Check digits are the first four bytes of SHA-256 over ASCII `myshell-recovery-v1`, one zero
byte, then the raw key. Importers require the exact prefix, alphabet, decoded length, and
checksum. The recovery key is shown only on explicit user request and is never uploaded or
logged. Losing it means Sync Hub ciphertext cannot be recovered on a new device.

## Failure behavior

Clients validate encoded/decoded size, checksum, envelope shape, nonce/tag lengths, AAD, GCM
authentication, UTF-8, then JSON schema—in that order. Any failure returns no plaintext, does
not advance the sync cursor, and does not replace a local record.
