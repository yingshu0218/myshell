package vault

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func openTestVault(t *testing.T) (*Vault, string) {
	t.Helper()
	directory := t.TempDir()
	keyPath := filepath.Join(directory, "key")
	key := []byte("0123456789abcdef0123456789abcdef")
	if err := os.WriteFile(keyPath, []byte(base64.RawStdEncoding.EncodeToString(key)), 0o600); err != nil {
		t.Fatal(err)
	}
	vault, err := Open(directory, keyPath)
	if err != nil {
		t.Fatal(err)
	}
	return vault, directory
}

func TestNewVaultSerializesConnectionsAsArray(t *testing.T) {
	dataVault, _ := openTestVault(t)
	payload, err := json.Marshal(dataVault.Snapshot())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(payload), `"connections":[]`) {
		t.Fatalf("new vault must expose an empty connections array: %s", payload)
	}
}

func TestVaultEncryptsCredentialsAndReloads(t *testing.T) {
	dataVault, directory := openTestVault(t)
	current := dataVault.Snapshot()
	current.Connections = []Connection{{
		ID: "id-1", Name: "server", Host: "example.test", Port: 22,
		Credential: Credential{Username: "tester", Password: "never-plaintext"},
	}}
	saved, err := dataVault.Replace(current.Version, current)
	if err != nil {
		t.Fatal(err)
	}
	onDisk, err := os.ReadFile(filepath.Join(directory, "vault.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(onDisk), "never-plaintext") || strings.Contains(string(onDisk), "tester") {
		t.Fatal("vault file contains plaintext credentials")
	}
	reloaded, err := Open(directory, filepath.Join(directory, "key"))
	if err != nil {
		t.Fatal(err)
	}
	if got := reloaded.Snapshot().Connections[0].Credential.Password; got != "never-plaintext" {
		t.Fatalf("password = %q", got)
	}
	if saved.Version != current.Version+1 {
		t.Fatalf("version = %d", saved.Version)
	}
}

func TestVaultConflictPreservesCurrentData(t *testing.T) {
	dataVault, _ := openTestVault(t)
	current := dataVault.Snapshot()
	current.Preferences.Theme = "nord"
	saved, err := dataVault.Replace(current.Version, current)
	if err != nil {
		t.Fatal(err)
	}
	stale := current
	stale.Preferences.Theme = "paper"
	actual, err := dataVault.Replace(current.Version, stale)
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("error = %v, want conflict", err)
	}
	if actual.Version != saved.Version || actual.Preferences.Theme != "nord" {
		t.Fatal("conflict response did not preserve current version")
	}
}

func TestRestoreRejectsTampering(t *testing.T) {
	dataVault, _ := openTestVault(t)
	envelope, err := dataVault.Envelope()
	if err != nil {
		t.Fatal(err)
	}
	envelope.Ciphertext = envelope.Ciphertext[:len(envelope.Ciphertext)-2] + "aa"
	if _, err := dataVault.RestoreEnvelope(dataVault.Snapshot().Version, envelope); err == nil {
		t.Fatal("tampered envelope was accepted")
	}
}

func TestVaultRejectsSSHArgumentInjection(t *testing.T) {
	dataVault, _ := openTestVault(t)
	current := dataVault.Snapshot()
	current.Connections = []Connection{{
		ID: "unsafe", Name: "unsafe", Host: "-oProxyCommand=bad", Port: 22,
	}}
	if _, err := dataVault.Replace(current.Version, current); err == nil {
		t.Fatal("option-like SSH host was accepted")
	}
}

func TestEnvelopePreviewOmitsCredentials(t *testing.T) {
	dataVault, _ := openTestVault(t)
	current := dataVault.Snapshot()
	current.Connections = []Connection{{
		ID: "preview", Name: "Preview Server", Host: "example.test", Port: 22,
		Credential: Credential{Username: "secret-user", Password: "secret-pass"},
	}}
	if _, err := dataVault.Replace(current.Version, current); err != nil {
		t.Fatal(err)
	}
	envelope, err := dataVault.Envelope()
	if err != nil {
		t.Fatal(err)
	}
	preview, err := dataVault.InspectEnvelope(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if preview.ConnectionCount != 1 || preview.ConnectionNames[0] != "Preview Server" {
		t.Fatalf("preview = %+v", preview)
	}
	encoded, _ := json.Marshal(preview)
	if strings.Contains(string(encoded), "secret-user") || strings.Contains(string(encoded), "secret-pass") {
		t.Fatal("preview exposed credentials")
	}
}

func TestVaultHistoryIsBounded(t *testing.T) {
	dataVault, directory := openTestVault(t)
	for index := 0; index < 9; index++ {
		current := dataVault.Snapshot()
		current.Preferences.Theme = "theme-" + strconv.Itoa(index)
		if _, err := dataVault.Replace(current.Version, current); err != nil {
			t.Fatal(err)
		}
	}
	entries, err := os.ReadDir(filepath.Join(directory, "history"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 5 {
		t.Fatalf("history files = %d, want 5", len(entries))
	}
}
