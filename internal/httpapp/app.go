package httpapp

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/yingshu0218/myshell/internal/auth"
	"github.com/yingshu0218/myshell/internal/backup"
	"github.com/yingshu0218/myshell/internal/config"
	"github.com/yingshu0218/myshell/internal/health"
	"github.com/yingshu0218/myshell/internal/terminal"
	"github.com/yingshu0218/myshell/internal/vault"
	webassets "github.com/yingshu0218/myshell/web"
)

const sessionCookie = "myshell_session"

type App struct {
	cfg       config.Config
	auth      *auth.Manager
	vault     *vault.Vault
	terminals *terminal.Manager
	checker   *health.Checker
	backups   *backup.Manager
	logger    *slog.Logger
	static    http.Handler

	healthMu       sync.RWMutex
	healthResults  map[string]health.Result
	started        time.Time
	configChanged  chan struct{}
	healthUnit     time.Duration
	dailyPeriod    time.Duration
	weeklyPeriod   time.Duration
	checkRequests  chan struct{}
	backupRequests chan struct{}
	requestSlots   chan struct{}
}

func New(cfg config.Config, authManager *auth.Manager, dataVault *vault.Vault, terminals *terminal.Manager, logger *slog.Logger) (*App, error) {
	staticFS, err := fs.Sub(webassets.Files, "dist")
	if err != nil {
		return nil, err
	}
	return &App{
		cfg: cfg, auth: authManager, vault: dataVault, terminals: terminals,
		checker: health.New(cfg.HealthTimeout, cfg.MaxHealthChecks),
		backups: backup.New(cfg.GitTokenFile), logger: logger,
		static:        http.FileServer(http.FS(staticFS)),
		healthResults: make(map[string]health.Result), started: time.Now(),
		configChanged: make(chan struct{}, 1),
		healthUnit:    time.Minute, dailyPeriod: 24 * time.Hour, weeklyPeriod: 7 * 24 * time.Hour,
		checkRequests: make(chan struct{}, 1), backupRequests: make(chan struct{}, 1),
		requestSlots: make(chan struct{}, 64),
	}, nil
}

func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", a.health)
	mux.HandleFunc("GET /api/session", a.session)
	mux.HandleFunc("POST /api/setup", a.setup)
	mux.HandleFunc("POST /api/login", a.login)
	mux.HandleFunc("POST /api/logout", a.protected(a.logout))
	mux.HandleFunc("GET /api/v1/vault", a.protected(a.getVault))
	mux.HandleFunc("PUT /api/v1/vault", a.protected(a.putVault))
	mux.HandleFunc("GET /api/v1/vault/envelope", a.protected(a.getEnvelope))
	mux.HandleFunc("PUT /api/v1/vault/envelope", a.protected(a.putEnvelope))
	mux.HandleFunc("GET /api/v1/terminals", a.protected(a.listTerminals))
	mux.HandleFunc("GET /api/v1/connections/{id}/host-key", a.protected(a.hostKeyStatus))
	mux.HandleFunc("POST /api/v1/connections/{id}/host-key/trust", a.protected(a.trustHostKey))
	mux.HandleFunc("POST /api/v1/terminals", a.protected(a.startTerminal))
	mux.HandleFunc("DELETE /api/v1/terminals/{id}", a.protected(a.closeTerminal))
	mux.HandleFunc("POST /api/v1/terminals/{id}/resize", a.protected(a.resizeTerminal))
	mux.HandleFunc("GET /api/v1/terminals/{id}/stream", a.protected(a.streamTerminal))
	mux.HandleFunc("GET /api/v1/status", a.protected(a.status))
	mux.HandleFunc("POST /api/v1/status/check", a.protected(a.checkStatus))
	mux.HandleFunc("GET /api/v1/backups", a.protected(a.listBackups))
	mux.HandleFunc("POST /api/v1/backups", a.protected(a.createBackup))
	mux.HandleFunc("POST /api/v1/backups/preview", a.protected(a.previewBackup))
	mux.HandleFunc("POST /api/v1/backups/restore", a.protected(a.restoreBackup))
	mux.HandleFunc("/", a.serveStatic)
	return a.limitRequests(a.requireHTTPS(a.securityHeaders(a.requestLog(mux))))
}

func (a *App) health(writer http.ResponseWriter, request *http.Request) {
	writeJSON(writer, http.StatusOK, map[string]any{
		"status": "healthy", "version": "dev", "uptimeSeconds": int(time.Since(a.started).Seconds()),
	})
}

func (a *App) session(writer http.ResponseWriter, request *http.Request) {
	response := map[string]any{"initialized": a.auth.Initialized(), "authenticated": false}
	if session, ok := a.currentSession(request); ok {
		username, _ := a.auth.Username()
		response["authenticated"] = true
		response["username"] = username
		response["csrfToken"] = session.CSRF
	}
	writeJSON(writer, http.StatusOK, response)
}

func (a *App) setup(writer http.ResponseWriter, request *http.Request) {
	if a.auth.Initialized() {
		writeError(writer, http.StatusConflict, "already_initialized", "Account has already been initialized.")
		return
	}
	var input credentials
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	if err := a.auth.Initialize(input.Username, input.Password); err != nil {
		writeError(writer, http.StatusBadRequest, "setup_failed", err.Error())
		return
	}
	a.loginWithCredentials(writer, request, input)
}

func (a *App) login(writer http.ResponseWriter, request *http.Request) {
	var input credentials
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	a.loginWithCredentials(writer, request, input)
}

func (a *App) loginWithCredentials(writer http.ResponseWriter, request *http.Request, input credentials) {
	session, err := a.auth.Login(input.Username, input.Password, remoteIP(request))
	if err != nil {
		status := http.StatusUnauthorized
		code := "invalid_login"
		if errors.Is(err, auth.ErrRateLimited) {
			status, code = http.StatusTooManyRequests, "rate_limited"
		}
		writeError(writer, status, code, "Unable to sign in.")
		return
	}
	http.SetCookie(writer, &http.Cookie{
		Name: sessionCookie, Value: session.ID, Path: "/", HttpOnly: true,
		Secure: a.cfg.SecureCookies, SameSite: http.SameSiteStrictMode,
		MaxAge: int(time.Until(session.ExpiresAt).Seconds()),
	})
	writeJSON(writer, http.StatusOK, map[string]string{"csrfToken": session.CSRF})
}

func (a *App) logout(writer http.ResponseWriter, request *http.Request) {
	if cookie, err := request.Cookie(sessionCookie); err == nil {
		a.auth.Logout(cookie.Value)
	}
	http.SetCookie(writer, &http.Cookie{
		Name: sessionCookie, Path: "/", MaxAge: -1, HttpOnly: true,
		Secure: a.cfg.SecureCookies, SameSite: http.SameSiteStrictMode,
	})
	writer.WriteHeader(http.StatusNoContent)
}

func (a *App) getVault(writer http.ResponseWriter, request *http.Request) {
	writeJSON(writer, http.StatusOK, a.vault.Snapshot())
}

func (a *App) putVault(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		ExpectedVersion uint64     `json:"expectedVersion"`
		Data            vault.Data `json:"data"`
	}
	if !decodeJSON(writer, request, &input, 1<<20) {
		return
	}
	result, err := a.vault.Replace(input.ExpectedVersion, input.Data)
	if errors.Is(err, vault.ErrConflict) {
		writeJSON(writer, http.StatusConflict, map[string]any{
			"error":   map[string]string{"code": "version_conflict", "message": "Vault changed on the server."},
			"current": result,
		})
		return
	}
	if err != nil {
		writeError(writer, http.StatusBadRequest, "invalid_vault", err.Error())
		return
	}
	select {
	case a.configChanged <- struct{}{}:
	default:
	}
	a.pruneHealth(result)
	writeJSON(writer, http.StatusOK, result)
}

func (a *App) getEnvelope(writer http.ResponseWriter, request *http.Request) {
	envelope, err := a.vault.Envelope()
	if err != nil {
		writeError(writer, http.StatusInternalServerError, "vault_failed", "Unable to create vault snapshot.")
		return
	}
	writeJSON(writer, http.StatusOK, envelope)
}

func (a *App) putEnvelope(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		ExpectedVersion uint64         `json:"expectedVersion"`
		Envelope        vault.Envelope `json:"envelope"`
	}
	if !decodeJSON(writer, request, &input, 2<<20) {
		return
	}
	result, err := a.vault.RestoreEnvelope(input.ExpectedVersion, input.Envelope)
	if errors.Is(err, vault.ErrConflict) {
		writeJSON(writer, http.StatusConflict, map[string]any{
			"error":   map[string]string{"code": "version_conflict", "message": "Vault changed on the server."},
			"current": result,
		})
		return
	}
	if err != nil {
		writeError(writer, http.StatusBadRequest, "invalid_envelope", err.Error())
		return
	}
	select {
	case a.configChanged <- struct{}{}:
	default:
	}
	a.pruneHealth(result)
	writeJSON(writer, http.StatusOK, result)
}

func (a *App) listTerminals(writer http.ResponseWriter, request *http.Request) {
	writeJSON(writer, http.StatusOK, a.terminals.List())
}

func (a *App) hostKeyStatus(writer http.ResponseWriter, request *http.Request) {
	connection, exists := a.vault.Find(request.PathValue("id"))
	if !exists {
		writeError(writer, http.StatusNotFound, "connection_not_found", "Connection does not exist.")
		return
	}
	status, err := a.terminals.HostKey(request.Context(), connection)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "host_key_failed", err.Error())
		return
	}
	writeJSON(writer, http.StatusOK, status)
}

func (a *App) trustHostKey(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Fingerprint string `json:"fingerprint"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	if err := a.terminals.TrustHostKey(request.PathValue("id"), input.Fingerprint); err != nil {
		writeError(writer, http.StatusBadRequest, "host_key_confirmation_failed", err.Error())
		return
	}
	writer.WriteHeader(http.StatusNoContent)
}

func (a *App) startTerminal(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Kind         string `json:"kind"`
		ConnectionID string `json:"connectionId"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	id, err := randomID()
	if err != nil {
		writeError(writer, http.StatusInternalServerError, "terminal_failed", "Unable to create terminal.")
		return
	}
	var session *terminal.Session
	if input.Kind == "ssh" {
		connection, exists := a.vault.Find(input.ConnectionID)
		if !exists {
			writeError(writer, http.StatusNotFound, "connection_not_found", "Connection does not exist.")
			return
		}
		session, err = a.terminals.StartSSH(context.Background(), id, connection)
	} else if input.Kind == "shell" {
		session, err = a.terminals.StartShell(context.Background(), id)
	} else {
		writeError(writer, http.StatusBadRequest, "invalid_terminal", "Terminal kind must be shell or ssh.")
		return
	}
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, terminal.ErrLimit) {
			status = http.StatusTooManyRequests
		}
		writeError(writer, status, "terminal_failed", err.Error())
		return
	}
	writeJSON(writer, http.StatusCreated, session)
}

func (a *App) closeTerminal(writer http.ResponseWriter, request *http.Request) {
	if err := a.terminals.Close(request.PathValue("id")); err != nil {
		writeError(writer, http.StatusNotFound, "terminal_not_found", "Terminal does not exist.")
		return
	}
	writer.WriteHeader(http.StatusNoContent)
}

func (a *App) resizeTerminal(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Rows uint16 `json:"rows"`
		Cols uint16 `json:"cols"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	if err := a.terminals.Resize(request.PathValue("id"), input.Rows, input.Cols); err != nil {
		writeError(writer, http.StatusBadRequest, "resize_failed", err.Error())
		return
	}
	writer.WriteHeader(http.StatusNoContent)
}

func (a *App) streamTerminal(writer http.ResponseWriter, request *http.Request) {
	session, exists := a.terminals.Get(request.PathValue("id"))
	if !exists {
		writeError(writer, http.StatusNotFound, "terminal_not_found", "Terminal does not exist.")
		return
	}
	connection, err := websocket.Accept(writer, request, &websocket.AcceptOptions{
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		return
	}
	defer connection.CloseNow()
	ctx, cancel := context.WithCancel(request.Context())
	defer cancel()
	go func() {
		defer cancel()
		for {
			messageType, reader, err := connection.Reader(ctx)
			if err != nil {
				_ = a.terminals.Close(session.ID)
				return
			}
			if messageType != websocket.MessageBinary {
				continue
			}
			if _, err := io.Copy(session, io.LimitReader(reader, 64<<10)); err != nil {
				return
			}
		}
	}()
	buffer := make([]byte, 32<<10)
	for {
		count, readErr := session.Read(buffer)
		if count > 0 {
			writeErr := connection.Write(ctx, websocket.MessageBinary, buffer[:count])
			if writeErr != nil {
				break
			}
		}
		if readErr != nil {
			break
		}
	}
	a.terminals.Close(session.ID)
}

func (a *App) status(writer http.ResponseWriter, request *http.Request) {
	a.healthMu.RLock()
	results := make([]health.Result, 0, len(a.healthResults))
	for _, result := range a.healthResults {
		results = append(results, result)
	}
	a.healthMu.RUnlock()
	writeJSON(writer, http.StatusOK, map[string]any{
		"relay":   map[string]any{"online": true, "uptimeSeconds": int(time.Since(a.started).Seconds())},
		"targets": results,
	})
}

func (a *App) checkStatus(writer http.ResponseWriter, request *http.Request) {
	select {
	case a.checkRequests <- struct{}{}:
		defer func() { <-a.checkRequests }()
	default:
		writeError(writer, http.StatusTooManyRequests, "check_in_progress", "A status check is already running.")
		return
	}
	var input struct {
		ConnectionID string `json:"connectionId"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	data := a.vault.Snapshot()
	targets := make([]health.Target, 0, len(data.Connections))
	for _, connection := range data.Connections {
		if connection.Deleted || (input.ConnectionID != "" && connection.ID != input.ConnectionID) {
			continue
		}
		targets = append(targets, health.Target{
			ID: connection.ID, Host: connection.Host, Port: connection.Port,
		})
	}
	results := a.checker.CheckAll(request.Context(), targets)
	a.healthMu.Lock()
	for _, result := range results {
		a.healthResults[result.ID] = result
	}
	a.healthMu.Unlock()
	writeJSON(writer, http.StatusOK, results)
}

func (a *App) listBackups(writer http.ResponseWriter, request *http.Request) {
	items, err := a.backups.List(request.Context(), a.vault.Snapshot().Backup)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "backup_failed", err.Error())
		return
	}
	writeJSON(writer, http.StatusOK, items)
}

func (a *App) createBackup(writer http.ResponseWriter, request *http.Request) {
	select {
	case a.backupRequests <- struct{}{}:
		defer func() { <-a.backupRequests }()
	default:
		writeError(writer, http.StatusTooManyRequests, "backup_in_progress", "A backup is already running.")
		return
	}
	envelope, err := a.vault.Envelope()
	if err != nil {
		writeError(writer, http.StatusInternalServerError, "backup_failed", "Unable to create snapshot.")
		return
	}
	item, err := a.backups.Save(request.Context(), a.vault.Snapshot().Backup, envelope)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "backup_failed", err.Error())
		return
	}
	writeJSON(writer, http.StatusCreated, item)
}

func (a *App) restoreBackup(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Path            string `json:"path"`
		ExpectedVersion uint64 `json:"expectedVersion"`
		Confirm         string `json:"confirm"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	if input.Confirm != "RESTORE" {
		writeError(writer, http.StatusBadRequest, "confirmation_required", "Type RESTORE to confirm.")
		return
	}
	envelope, err := a.backups.Load(request.Context(), a.vault.Snapshot().Backup, input.Path)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "restore_failed", err.Error())
		return
	}
	result, err := a.vault.RestoreEnvelope(input.ExpectedVersion, envelope)
	if errors.Is(err, vault.ErrConflict) {
		writeJSON(writer, http.StatusConflict, map[string]any{"current": result})
		return
	}
	if err != nil {
		writeError(writer, http.StatusBadRequest, "restore_failed", err.Error())
		return
	}
	select {
	case a.configChanged <- struct{}{}:
	default:
	}
	a.pruneHealth(result)
	writeJSON(writer, http.StatusOK, result)
}

func (a *App) previewBackup(writer http.ResponseWriter, request *http.Request) {
	var input struct {
		Path string `json:"path"`
	}
	if !decodeJSON(writer, request, &input, 4096) {
		return
	}
	envelope, err := a.backups.Load(request.Context(), a.vault.Snapshot().Backup, input.Path)
	if err != nil {
		writeError(writer, http.StatusBadGateway, "preview_failed", err.Error())
		return
	}
	preview, err := a.vault.InspectEnvelope(envelope)
	if err != nil {
		writeError(writer, http.StatusBadRequest, "preview_failed", err.Error())
		return
	}
	writeJSON(writer, http.StatusOK, preview)
}

func (a *App) protected(next http.HandlerFunc) http.HandlerFunc {
	return func(writer http.ResponseWriter, request *http.Request) {
		session, ok := a.currentSession(request)
		if !ok {
			writeError(writer, http.StatusUnauthorized, "authentication_required", "Sign in required.")
			return
		}
		if request.Method != http.MethodGet && request.Header.Get("X-CSRF-Token") != session.CSRF {
			writeError(writer, http.StatusForbidden, "csrf_failed", "Security token is invalid.")
			return
		}
		next(writer, request)
	}
}

func (a *App) currentSession(request *http.Request) (*auth.Session, bool) {
	cookie, err := request.Cookie(sessionCookie)
	if err != nil {
		return nil, false
	}
	return a.auth.Validate(cookie.Value)
}

func (a *App) serveStatic(writer http.ResponseWriter, request *http.Request) {
	if request.URL.Path != "/" && strings.Contains(pathClean(request.URL.Path), "..") {
		http.NotFound(writer, request)
		return
	}
	a.static.ServeHTTP(writer, request)
}

func (a *App) requestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		start := time.Now()
		next.ServeHTTP(writer, request)
		a.logger.Info("http request", "method", request.Method, "path", request.URL.Path,
			"duration_ms", time.Since(start).Milliseconds(), "remote", remoteIP(request))
	})
}

func (a *App) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("X-Frame-Options", "DENY")
		writer.Header().Set("Referrer-Policy", "no-referrer")
		writer.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		writer.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'")
		if a.cfg.SecureCookies {
			writer.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(writer, request)
	})
}

func (a *App) requireHTTPS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if !a.cfg.SecureCookies || request.URL.Path == "/health" ||
			request.TLS != nil || request.Header.Get("X-Forwarded-Proto") == "https" {
			next.ServeHTTP(writer, request)
			return
		}
		writer.Header().Set("Connection", "close")
		writeError(writer, http.StatusUpgradeRequired, "https_required", "MyShell requires HTTPS.")
	})
}

func (a *App) limitRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		select {
		case a.requestSlots <- struct{}{}:
			defer func() { <-a.requestSlots }()
			next.ServeHTTP(writer, request)
		default:
			writeError(writer, http.StatusServiceUnavailable, "server_busy", "MyShell is busy; try again shortly.")
		}
	})
}

type credentials struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func decodeJSON(writer http.ResponseWriter, request *http.Request, target any, limit int64) bool {
	request.Body = http.MaxBytesReader(writer, request.Body, limit)
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(writer, http.StatusBadRequest, "invalid_request", "Request body is invalid.")
		return false
	}
	return true
}

func writeJSON(writer http.ResponseWriter, status int, value any) {
	writer.Header().Set("Content-Type", "application/json")
	writer.WriteHeader(status)
	_ = json.NewEncoder(writer).Encode(value)
}

func writeError(writer http.ResponseWriter, status int, code, message string) {
	writeJSON(writer, status, map[string]any{
		"error": map[string]string{"code": code, "message": message},
	})
}

func randomID() (string, error) {
	data := make([]byte, 16)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return hex.EncodeToString(data), nil
}

func remoteIP(request *http.Request) string {
	host, _, err := net.SplitHostPort(request.RemoteAddr)
	if err == nil {
		return host
	}
	return request.RemoteAddr
}

func pathClean(value string) string {
	parsed, err := url.PathUnescape(value)
	if err != nil {
		return value
	}
	return parsed
}

func ParseUint16(value string) uint16 {
	parsed, _ := strconv.ParseUint(value, 10, 16)
	return uint16(parsed)
}

func (a *App) RunBackground(ctx context.Context) {
	nextChecks := make(map[string]time.Time)
	var nextBackup time.Time
	var timer *time.Timer
	for {
		now := time.Now()
		data := a.vault.Snapshot()
		var nearest time.Time
		var dueTargets []health.Target
		active := make(map[string]bool)
		for _, connection := range data.Connections {
			if connection.Deleted || connection.HealthPeriod == 0 {
				continue
			}
			active[connection.ID] = true
			due := nextChecks[connection.ID]
			if due.IsZero() {
				due = now.Add(time.Duration(connection.HealthPeriod) * a.healthUnit)
				nextChecks[connection.ID] = due
			}
			if !due.After(now) {
				dueTargets = append(dueTargets, health.Target{
					ID: connection.ID, Host: connection.Host, Port: connection.Port,
				})
				due = now.Add(time.Duration(connection.HealthPeriod) * a.healthUnit)
				nextChecks[connection.ID] = due
			}
			nearest = earlier(nearest, due)
		}
		if len(dueTargets) > 0 {
			go a.runScheduledChecks(ctx, dueTargets)
		}
		for id := range nextChecks {
			if !active[id] {
				delete(nextChecks, id)
			}
		}
		if data.Backup.Enabled && data.Backup.Schedule != "" {
			period := a.dailyPeriod
			if data.Backup.Schedule == "weekly" {
				period = a.weeklyPeriod
			}
			if nextBackup.IsZero() {
				nextBackup = now.Add(period)
			}
			if !nextBackup.After(now) {
				go a.runScheduledBackup(ctx, data.Backup)
				nextBackup = now.Add(period)
			}
			nearest = earlier(nearest, nextBackup)
		} else {
			nextBackup = time.Time{}
		}

		var timerChannel <-chan time.Time
		if !nearest.IsZero() {
			wait := time.Until(nearest)
			if wait < time.Millisecond {
				wait = time.Millisecond
			}
			if timer == nil {
				timer = time.NewTimer(wait)
			} else {
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				timer.Reset(wait)
			}
			timerChannel = timer.C
		}
		select {
		case <-ctx.Done():
			if timer != nil {
				timer.Stop()
			}
			return
		case <-a.configChanged:
		case <-timerChannel:
		}
	}
}

func (a *App) runScheduledChecks(ctx context.Context, targets []health.Target) {
	results := a.checker.CheckAll(ctx, targets)
	a.healthMu.Lock()
	for _, result := range results {
		a.healthResults[result.ID] = result
	}
	a.healthMu.Unlock()
}

func (a *App) runScheduledBackup(ctx context.Context, config vault.BackupConfig) {
	select {
	case a.backupRequests <- struct{}{}:
		defer func() { <-a.backupRequests }()
	default:
		return
	}
	envelope, err := a.vault.Envelope()
	if err != nil {
		a.logger.Error("scheduled backup failed", "reason", "snapshot")
		return
	}
	if _, err := a.backups.Save(ctx, config, envelope); err != nil {
		a.logger.Error("scheduled backup failed", "reason", "provider")
	}
}

func earlier(current, candidate time.Time) time.Time {
	if current.IsZero() || candidate.Before(current) {
		return candidate
	}
	return current
}

func (a *App) pruneHealth(data vault.Data) {
	active := make(map[string]struct{}, len(data.Connections))
	for _, connection := range data.Connections {
		if !connection.Deleted {
			active[connection.ID] = struct{}{}
		}
	}
	a.healthMu.Lock()
	for id := range a.healthResults {
		if _, ok := active[id]; !ok {
			delete(a.healthResults, id)
		}
	}
	a.healthMu.Unlock()
}
