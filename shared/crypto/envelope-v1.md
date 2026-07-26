# MyShell Sync Envelope v1

This format encrypts one Sync Hub record independently. It is separate from the
local `vault.json` envelope.

## Inputs

- Key: exactly 32 bytes.
- Nonce: exactly 12 unique random bytes for every encryption.
- Plaintext: UTF-8 JSON conforming to the collection's versioned schema.
- IDs: 1–128 ASCII characters from `[A-Za-z0-9._-]`.
- Schema version: positive decimal integer.

The authenticated additional data is the exact UTF-8 byte sequence:

```text
myshell-sync|v1|{appId}|{collection}|{recordId}|{schemaVersion}
```

## Payload

AES-256-GCM produces `ciphertext || 16-byte tag`. The bytes sent as Sync Hub's
`payload` are:

```text
4d 53 01 || 12-byte nonce || ciphertext || 16-byte GCM tag
```

`4d 53` is ASCII `MS`; `01` is the envelope version. Sync Hub's JSON encoding
base64-encodes these bytes. `checksum` is base64url without padding of
SHA-256 over the complete payload bytes. The checksum detects accidental
transport corruption; successful GCM authentication is still mandatory.

Reject unknown headers, payloads shorter than 32 bytes, invalid IDs, unsupported
schema versions, authentication failures, or plaintext larger than 1 MiB.
Never log inputs, payload, checksum, key, nonce, plaintext, or decrypted values.

## JSON serialization

Record producers write fields in the order shown by the corresponding schema
and use UTF-8 without a BOM or insignificant whitespace. Readers must not depend
on field order. Times are UTC RFC 3339. Unknown fields are rejected in v1.

## Key handling

The Web client reads the key from the read-only `vault_key` Docker Secret.
The Sync Hub token is a separate secret and cannot decrypt records. New native
clients import the same recovery key once into their platform credential store.
