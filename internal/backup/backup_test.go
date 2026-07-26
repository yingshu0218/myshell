package backup

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yingshu0218/myshell/internal/vault"
)

func TestGiteaBackupSaveListAndLoad(t *testing.T) {
	var saved []byte
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Header.Get("Authorization") != "token secret-token" {
			http.Error(writer, "unauthorized", http.StatusUnauthorized)
			return
		}
		switch {
		case request.Method == http.MethodPost && strings.Contains(request.URL.Path, "/contents/backups/vault-"):
			var input struct {
				Content string `json:"content"`
			}
			if err := json.NewDecoder(request.Body).Decode(&input); err != nil {
				http.Error(writer, "bad request", http.StatusBadRequest)
				return
			}
			saved, _ = base64.StdEncoding.DecodeString(input.Content)
			writer.WriteHeader(http.StatusCreated)
			writer.Write([]byte(`{"content":{"sha":"saved-sha"}}`))
		case request.Method == http.MethodGet && strings.HasSuffix(request.URL.Path, "/contents/backups"):
			writer.Header().Set("Content-Type", "application/json")
			writer.Write([]byte(`[{"name":"vault-test-v2.json","path":"backups/vault-test-v2.json","sha":"abc","size":123}]`))
		case request.Method == http.MethodGet && strings.HasSuffix(request.URL.Path, "/contents/backups/vault-test-v2.json"):
			writer.Header().Set("Content-Type", "application/json")
			json.NewEncoder(writer).Encode(map[string]string{"content": base64.StdEncoding.EncodeToString(saved)})
		default:
			http.NotFound(writer, request)
		}
	}))
	defer server.Close()

	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("secret-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	manager := New(tokenPath)
	config := vault.BackupConfig{
		Enabled: true, Provider: "gitea", APIBase: server.URL,
		Owner: "owner", Repo: "vault", Branch: "main",
	}
	envelope := vault.Envelope{
		Format: "myshell-aes-256-gcm-v1", Version: 2, Nonce: "nonce",
		Ciphertext: "ciphertext", UpdatedAt: "2026-07-26T00:00:00Z",
	}
	if _, err := manager.Save(context.Background(), config, envelope); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(saved), "secret-token") {
		t.Fatal("token was written into backup payload")
	}
	items, err := manager.List(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Fatalf("backup count = %d", len(items))
	}
	loaded, err := manager.Load(context.Background(), config, items[0].Path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Version != envelope.Version || loaded.Ciphertext != envelope.Ciphertext {
		t.Fatalf("loaded envelope = %+v", loaded)
	}
}

func TestBackupRejectsPathTraversal(t *testing.T) {
	manager := New(filepath.Join(t.TempDir(), "missing"))
	config := vault.BackupConfig{Enabled: true, Provider: "github", Owner: "o", Repo: "r", Branch: "main"}
	if _, err := manager.Load(context.Background(), config, "../vault.json"); err == nil {
		t.Fatal("path traversal was accepted")
	}
}

func TestGitHubBackupUsesContentsAPI(t *testing.T) {
	var called bool
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		called = true
		if request.Method != http.MethodPut {
			t.Errorf("method = %s, want PUT", request.Method)
		}
		if request.Header.Get("Authorization") != "Bearer github-token" {
			t.Errorf("authorization header is incorrect")
		}
		if request.URL.Query().Has("ref") {
			t.Errorf("create request must put branch in body, not ref query")
		}
		writer.WriteHeader(http.StatusCreated)
		writer.Write([]byte(`{"content":{"sha":"new"}}`))
	}))
	defer server.Close()
	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("github-token"), 0o600); err != nil {
		t.Fatal(err)
	}
	manager := New(tokenPath)
	config := vault.BackupConfig{
		Enabled: true, Provider: "github", APIBase: server.URL,
		Owner: "owner", Repo: "repo", Branch: "main",
	}
	if _, err := manager.Save(context.Background(), config, vault.Envelope{
		Format: "myshell-aes-256-gcm-v1", Version: 1, Nonce: "n", Ciphertext: "c",
	}); err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("GitHub API was not called")
	}
}
