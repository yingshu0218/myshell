package syncproto

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

type vectorContext struct {
	AppID         string `json:"appId"`
	Collection    string `json:"collection"`
	RecordID      string `json:"recordId"`
	SchemaVersion int    `json:"schemaVersion"`
}

type envelopeVector struct {
	Key       string        `json:"keyBase64Raw"`
	Nonce     string        `json:"nonceBase64Raw"`
	Context   vectorContext `json:"context"`
	Plaintext string        `json:"plaintext"`
	Payload   string        `json:"payloadBase64"`
	Checksum  string        `json:"checksumBase64URLRaw"`
}

func TestEnvelopeV1Vector(t *testing.T) {
	vector := readVector[envelopeVector](t, "envelope-v1.json")
	key := decodeRaw(t, vector.Key)
	nonce := decodeRaw(t, vector.Nonce)
	context := toContext(vector.Context)

	payload, checksum, err := SealWithNonce(key, nonce, []byte(vector.Plaintext), context)
	if err != nil {
		t.Fatal(err)
	}
	if got := base64.StdEncoding.EncodeToString(payload); got != vector.Payload {
		t.Fatalf("payload does not match shared vector")
	}
	if checksum != vector.Checksum {
		t.Fatalf("checksum does not match shared vector")
	}
	plaintext, err := Open(key, payload, checksum, context)
	if err != nil {
		t.Fatal(err)
	}
	if string(plaintext) != vector.Plaintext {
		t.Fatalf("plaintext does not round trip")
	}
}

func TestEnvelopeRejectsChangedAAD(t *testing.T) {
	base := readVector[envelopeVector](t, "envelope-v1.json")
	invalid := readVector[struct {
		Context vectorContext `json:"changedContext"`
	}](t, "invalid-aad-v1.json")
	payload, err := base64.StdEncoding.DecodeString(base.Payload)
	if err != nil {
		t.Fatal(err)
	}
	_, err = Open(decodeRaw(t, base.Key), payload, base.Checksum, toContext(invalid.Context))
	if !errors.Is(err, ErrAuth) {
		t.Fatalf("expected authentication failure, got %v", err)
	}
}

func TestEnvelopeRejectsCorruptedCiphertext(t *testing.T) {
	base := readVector[envelopeVector](t, "envelope-v1.json")
	mutation := readVector[struct {
		Mutation struct {
			Index int  `json:"payloadByteIndex"`
			XOR   byte `json:"xor"`
		} `json:"mutation"`
	}](t, "corrupted-ciphertext-v1.json")
	payload, err := base64.StdEncoding.DecodeString(base.Payload)
	if err != nil {
		t.Fatal(err)
	}
	payload[mutation.Mutation.Index] ^= mutation.Mutation.XOR
	_, err = Open(decodeRaw(t, base.Key), payload, base.Checksum, toContext(base.Context))
	if !errors.Is(err, ErrInvalid) {
		t.Fatalf("expected invalid envelope, got %v", err)
	}
}

func TestEnvelopeBounds(t *testing.T) {
	key := make([]byte, 32)
	nonce := make([]byte, 12)
	context := Context{AppID: "myshell", Collection: "connections", RecordID: "record-1", SchemaVersion: 1}
	if _, _, err := SealWithNonce(key, nonce, make([]byte, MaxPlaintext+1), context); !errors.Is(err, ErrInvalid) {
		t.Fatalf("expected oversized plaintext rejection, got %v", err)
	}
	context.RecordID = "invalid/id"
	if _, _, err := SealWithNonce(key, nonce, nil, context); !errors.Is(err, ErrInvalid) {
		t.Fatalf("expected invalid identifier rejection, got %v", err)
	}
}

func readVector[T any](t *testing.T, name string) T {
	t.Helper()
	path := filepath.Join("..", "..", "shared", "test-vectors", name)
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var value T
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatal(err)
	}
	return value
}

func decodeRaw(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := base64.RawStdEncoding.DecodeString(value)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}

func toContext(value vectorContext) Context {
	return Context{
		AppID: value.AppID, Collection: value.Collection,
		RecordID: value.RecordID, SchemaVersion: value.SchemaVersion,
	}
}
