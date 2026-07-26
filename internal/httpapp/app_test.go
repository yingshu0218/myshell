package httpapp

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/yingshu0218/myshell/internal/auth"
	"github.com/yingshu0218/myshell/internal/config"
	"github.com/yingshu0218/myshell/internal/terminal"
	"github.com/yingshu0218/myshell/internal/vault"
)

func newHTTPTestServer(t *testing.T) (*httptest.Server, *auth.Manager, *vault.Vault, string) {
	t.Helper()
	dataDir := t.TempDir()
	keyPath := filepath.Join(dataDir, "vault-key")
	key := base64.RawStdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef"))
	if err := os.WriteFile(keyPath, []byte(key), 0o600); err != nil {
		t.Fatal(err)
	}
	authManager, err := auth.New(dataDir, 30*time.Minute, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	dataVault, err := vault.Open(dataDir, keyPath)
	if err != nil {
		t.Fatal(err)
	}
	terminals, err := terminal.New(2, "/bin/sh", dataDir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(terminals.CloseAll)
	cfg := config.Config{
		DataDir: dataDir, Shell: "/bin/sh", SecureCookies: false,
		SessionIdle: 30 * time.Minute, SessionAbsolute: time.Hour,
		MaxTerminals: 2, MaxHealthChecks: 1, HealthTimeout: time.Second,
		VaultKeyFile: keyPath, GitTokenFile: filepath.Join(dataDir, "token"),
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	app, err := New(cfg, authManager, dataVault, terminals, logger)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(app.Handler())
	t.Cleanup(server.Close)
	return server, authManager, dataVault, dataDir
}

func TestSetupLoginCSRFAndVaultConflict(t *testing.T) {
	server, _, _, dataDir := newHTTPTestServer(t)
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}

	setup := requestJSON(t, client, http.MethodPost, server.URL+"/api/setup", map[string]string{
		"username": "111111", "password": "111111",
	}, "")
	if setup.StatusCode != http.StatusOK {
		t.Fatalf("setup status = %d: %s", setup.StatusCode, readBody(setup))
	}
	var login struct {
		CSRF string `json:"csrfToken"`
	}
	decodeResponse(t, setup, &login)
	if login.CSRF == "" {
		t.Fatal("setup did not create a CSRF token")
	}
	accountFile, err := os.ReadFile(filepath.Join(dataDir, "account.json"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(accountFile, []byte(`"password":"111111"`)) ||
		bytes.Contains(accountFile, []byte(`"password": "111111"`)) {
		t.Fatal("account file contains the test password in plaintext")
	}

	withoutCSRF := requestJSON(t, client, http.MethodPut, server.URL+"/api/v1/vault", map[string]any{}, "")
	if withoutCSRF.StatusCode != http.StatusForbidden {
		t.Fatalf("missing CSRF status = %d", withoutCSRF.StatusCode)
	}
	withoutCSRF.Body.Close()

	get, err := client.Get(server.URL + "/api/v1/vault")
	if err != nil {
		t.Fatal(err)
	}
	var current vault.Data
	decodeResponse(t, get, &current)
	current.Preferences.Theme = "nord"
	saved := requestJSON(t, client, http.MethodPut, server.URL+"/api/v1/vault", map[string]any{
		"expectedVersion": current.Version, "data": current,
	}, login.CSRF)
	if saved.StatusCode != http.StatusOK {
		t.Fatalf("save status = %d: %s", saved.StatusCode, readBody(saved))
	}
	saved.Body.Close()

	stale := requestJSON(t, client, http.MethodPut, server.URL+"/api/v1/vault", map[string]any{
		"expectedVersion": current.Version, "data": current,
	}, login.CSRF)
	if stale.StatusCode != http.StatusConflict {
		t.Fatalf("stale update status = %d: %s", stale.StatusCode, readBody(stale))
	}
	stale.Body.Close()
}

func TestPasswordResetInvalidatesHTTPSession(t *testing.T) {
	server, manager, _, _ := newHTTPTestServer(t)
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}
	login := requestJSON(t, client, http.MethodPost, server.URL+"/api/login", map[string]string{
		"username": "111111", "password": "111111",
	}, "")
	if login.StatusCode != http.StatusOK {
		t.Fatalf("login status = %d", login.StatusCode)
	}
	login.Body.Close()
	if err := manager.ResetPassword("222222"); err != nil {
		t.Fatal(err)
	}
	response, err := client.Get(server.URL + "/api/v1/vault")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status after reset = %d", response.StatusCode)
	}
}

func TestScheduledHealthCheckRunsOnlyWhenConfigured(t *testing.T) {
	dataDir := t.TempDir()
	keyPath := filepath.Join(dataDir, "vault-key")
	key := base64.RawStdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef"))
	if err := os.WriteFile(keyPath, []byte(key), 0o600); err != nil {
		t.Fatal(err)
	}
	dataVault, err := vault.Open(dataDir, keyPath)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	host, portText, _ := net.SplitHostPort(listener.Addr().String())
	port, _ := strconv.Atoi(portText)
	current := dataVault.Snapshot()
	current.Connections = []vault.Connection{{
		ID: "scheduled", Name: "scheduled", Host: host, Port: port, HealthPeriod: 5,
	}}
	if _, err := dataVault.Replace(current.Version, current); err != nil {
		t.Fatal(err)
	}
	authManager, _ := auth.New(dataDir, time.Minute, time.Hour)
	terminals, _ := terminal.New(1, "/bin/sh", dataDir)
	defer terminals.CloseAll()
	app, err := New(config.Config{
		DataDir: dataDir, Shell: "/bin/sh", MaxTerminals: 1, MaxHealthChecks: 1,
		HealthTimeout: time.Second, VaultKeyFile: keyPath,
	}, authManager, dataVault, terminals, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	app.healthUnit = 2 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go app.RunBackground(ctx)
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		app.healthMu.RLock()
		result, ok := app.healthResults["scheduled"]
		app.healthMu.RUnlock()
		if ok {
			if !result.Online {
				t.Fatalf("scheduled result = %+v", result)
			}
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("scheduled health check did not run")
}

func TestScheduledBackupRuns(t *testing.T) {
	var calls atomic.Int32
	provider := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.Header.Get("Authorization") != "token test-token" {
			http.Error(writer, "unexpected request", http.StatusBadRequest)
			return
		}
		calls.Add(1)
		writer.WriteHeader(http.StatusCreated)
		writer.Write([]byte(`{"content":{"sha":"ok"}}`))
	}))
	defer provider.Close()

	_, _, _, dataDir := newHTTPTestServer(t)
	keyPath := filepath.Join(dataDir, "vault-key")
	dataVault, err := vault.Open(dataDir, keyPath)
	if err != nil {
		t.Fatal(err)
	}
	tokenPath := filepath.Join(dataDir, "token")
	if err := os.WriteFile(tokenPath, []byte("test-token"), 0o600); err != nil {
		t.Fatal(err)
	}
	current := dataVault.Snapshot()
	current.Backup = vault.BackupConfig{
		Enabled: true, Provider: "gitea", APIBase: provider.URL,
		Owner: "owner", Repo: "repo", Branch: "main", Schedule: "daily",
	}
	if _, err := dataVault.Replace(current.Version, current); err != nil {
		t.Fatal(err)
	}
	authManager, _ := auth.New(dataDir, time.Minute, time.Hour)
	terminals, _ := terminal.New(1, "/bin/sh", dataDir)
	defer terminals.CloseAll()
	app, err := New(config.Config{
		DataDir: dataDir, Shell: "/bin/sh", MaxTerminals: 1, MaxHealthChecks: 1,
		HealthTimeout: time.Second, VaultKeyFile: keyPath, GitTokenFile: tokenPath,
	}, authManager, dataVault, terminals, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	app.dailyPeriod = 10 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go app.RunBackground(ctx)
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if calls.Load() > 0 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("scheduled backup did not run")
}

func TestWebSocketPTYRoundTripAndCleanup(t *testing.T) {
	server, manager, _, _ := newHTTPTestServer(t)
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}
	login := requestJSON(t, client, http.MethodPost, server.URL+"/api/login", map[string]string{
		"username": "111111", "password": "111111",
	}, "")
	var loginPayload struct {
		CSRF string `json:"csrfToken"`
	}
	decodeResponse(t, login, &loginPayload)
	create := requestJSON(t, client, http.MethodPost, server.URL+"/api/v1/terminals", map[string]string{
		"kind": "shell",
	}, loginPayload.CSRF)
	if create.StatusCode != http.StatusCreated {
		t.Fatalf("create status = %d: %s", create.StatusCode, readBody(create))
	}
	var session struct {
		ID string `json:"id"`
	}
	decodeResponse(t, create, &session)
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/terminals/" + session.ID + "/stream"
	header := http.Header{}
	for _, cookie := range jar.Cookies(mustParseURL(t, server.URL)) {
		header.Add("Cookie", cookie.String())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(ctx, endpoint, &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatal(err)
	}
	defer connection.CloseNow()
	if err := connection.Write(ctx, websocket.MessageBinary, []byte("printf 'websocket-pty-ok\\n'\nexit\n")); err != nil {
		t.Fatal(err)
	}
	var output strings.Builder
	for !strings.Contains(output.String(), "websocket-pty-ok") {
		messageType, data, err := connection.Read(ctx)
		if err != nil {
			t.Fatalf("read terminal: %v; output=%q", err, output.String())
		}
		if messageType == websocket.MessageBinary {
			output.Write(data)
		}
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		response, err := client.Get(server.URL + "/api/v1/terminals")
		if err != nil {
			t.Fatal(err)
		}
		var sessions []map[string]any
		decodeResponse(t, response, &sessions)
		if len(sessions) == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("terminal session was not cleaned up after shell exit")
}

func TestWebSocketDisconnectCleansUpPTY(t *testing.T) {
	server, manager, _, _ := newHTTPTestServer(t)
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}
	login := requestJSON(t, client, http.MethodPost, server.URL+"/api/login", map[string]string{
		"username": "111111", "password": "111111",
	}, "")
	var loginPayload struct {
		CSRF string `json:"csrfToken"`
	}
	decodeResponse(t, login, &loginPayload)
	create := requestJSON(t, client, http.MethodPost, server.URL+"/api/v1/terminals", map[string]string{
		"kind": "shell",
	}, loginPayload.CSRF)
	if create.StatusCode != http.StatusCreated {
		t.Fatalf("create status = %d: %s", create.StatusCode, readBody(create))
	}
	var session struct {
		ID string `json:"id"`
	}
	decodeResponse(t, create, &session)
	endpoint := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/terminals/" + session.ID + "/stream"
	header := http.Header{}
	for _, cookie := range jar.Cookies(mustParseURL(t, server.URL)) {
		header.Add("Cookie", cookie.String())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(ctx, endpoint, &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatal(err)
	}
	connection.CloseNow()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		response, err := client.Get(server.URL + "/api/v1/terminals")
		if err != nil {
			t.Fatal(err)
		}
		var sessions []map[string]any
		decodeResponse(t, response, &sessions)
		if len(sessions) == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("terminal session was not cleaned up after websocket disconnect")
}

func TestBackupPreviewAndConfirmedRestore(t *testing.T) {
	var backupPayload []byte
	provider := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || !strings.HasSuffix(request.URL.Path, "/contents/backups/vault-restore.json") {
			http.NotFound(writer, request)
			return
		}
		json.NewEncoder(writer).Encode(map[string]string{
			"content": base64.StdEncoding.EncodeToString(backupPayload),
		})
	}))
	defer provider.Close()

	server, manager, dataVault, dataDir := newHTTPTestServer(t)
	if err := os.WriteFile(filepath.Join(dataDir, "token"), []byte("token"), 0o600); err != nil {
		t.Fatal(err)
	}
	current := dataVault.Snapshot()
	current.Backup = vault.BackupConfig{
		Enabled: true, Provider: "gitea", APIBase: provider.URL,
		Owner: "owner", Repo: "repo", Branch: "main",
	}
	current.Connections = []vault.Connection{{
		ID: "backup-server", Name: "Backup Server", Host: "example.test", Port: 22,
		Credential: vault.Credential{Username: "user", Password: "password"},
	}}
	snapshotVersion, err := dataVault.Replace(current.Version, current)
	if err != nil {
		t.Fatal(err)
	}
	envelope, err := dataVault.Envelope()
	if err != nil {
		t.Fatal(err)
	}
	backupPayload, _ = json.Marshal(envelope)
	modified := snapshotVersion
	modified.Preferences.Theme = "nord"
	latest, err := dataVault.Replace(modified.Version, modified)
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar}
	login := requestJSON(t, client, http.MethodPost, server.URL+"/api/login", map[string]string{
		"username": "111111", "password": "111111",
	}, "")
	var loginPayload struct {
		CSRF string `json:"csrfToken"`
	}
	decodeResponse(t, login, &loginPayload)
	path := "backups/vault-restore.json"
	previewResponse := requestJSON(t, client, http.MethodPost, server.URL+"/api/v1/backups/preview", map[string]string{
		"path": path,
	}, loginPayload.CSRF)
	if previewResponse.StatusCode != http.StatusOK {
		t.Fatalf("preview status = %d: %s", previewResponse.StatusCode, readBody(previewResponse))
	}
	var preview vault.Preview
	decodeResponse(t, previewResponse, &preview)
	if preview.ConnectionCount != 1 || preview.ConnectionNames[0] != "Backup Server" {
		t.Fatalf("preview = %+v", preview)
	}
	unconfirmed := requestJSON(t, client, http.MethodPost, server.URL+"/api/v1/backups/restore", map[string]any{
		"path": path, "expectedVersion": latest.Version, "confirm": "",
	}, loginPayload.CSRF)
	if unconfirmed.StatusCode != http.StatusBadRequest {
		t.Fatalf("unconfirmed restore status = %d", unconfirmed.StatusCode)
	}
	unconfirmed.Body.Close()
	restoreResponse := requestJSON(t, client, http.MethodPost, server.URL+"/api/v1/backups/restore", map[string]any{
		"path": path, "expectedVersion": latest.Version, "confirm": "RESTORE",
	}, loginPayload.CSRF)
	if restoreResponse.StatusCode != http.StatusOK {
		t.Fatalf("restore status = %d: %s", restoreResponse.StatusCode, readBody(restoreResponse))
	}
	var restored vault.Data
	decodeResponse(t, restoreResponse, &restored)
	if restored.Version != latest.Version+1 || restored.Preferences.Theme != snapshotVersion.Preferences.Theme {
		t.Fatalf("restored vault = %+v", restored)
	}
}

func mustParseURL(t *testing.T, value string) *url.URL {
	t.Helper()
	parsed, err := url.Parse(value)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func requestJSON(t *testing.T, client *http.Client, method, endpoint string, payload any, csrf string) *http.Response {
	t.Helper()
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	request, err := http.NewRequest(method, endpoint, bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	if csrf != "" {
		request.Header.Set("X-CSRF-Token", csrf)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func decodeResponse(t *testing.T, response *http.Response, target any) {
	t.Helper()
	defer response.Body.Close()
	if err := json.NewDecoder(response.Body).Decode(target); err != nil {
		t.Fatal(err)
	}
}

func readBody(response *http.Response) string {
	defer response.Body.Close()
	data, _ := io.ReadAll(response.Body)
	return string(data)
}
