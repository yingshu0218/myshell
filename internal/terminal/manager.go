package terminal

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/creack/pty"
	"github.com/yingshu0218/myshell/internal/vault"
)

var (
	ErrLimit       = errors.New("terminal session limit reached")
	ErrNotFound    = errors.New("terminal session not found")
	ErrInvalidSize = errors.New("invalid terminal size")
)

type Session struct {
	ID        string    `json:"id"`
	Kind      string    `json:"kind"`
	Label     string    `json:"label"`
	CreatedAt time.Time `json:"createdAt"`

	mu      sync.Mutex
	ptmx    *os.File
	command *exec.Cmd
	done    chan struct{}
	once    sync.Once
}

type Manager struct {
	mu          sync.Mutex
	sessions    map[string]*Session
	starting    int
	max         int
	shell       string
	dataDir     string
	executable  string
	hostKeyMu   sync.Mutex
	pendingKeys map[string]pendingHostKey
}

type pendingHostKey struct {
	line        string
	fingerprint string
	expiresAt   time.Time
}

type HostKeyStatus struct {
	Trusted     bool   `json:"trusted"`
	Fingerprint string `json:"fingerprint,omitempty"`
	Algorithm   string `json:"algorithm,omitempty"`
}

func New(max int, shell, dataDir string) (*Manager, error) {
	executable, err := os.Executable()
	if err != nil {
		return nil, err
	}
	return &Manager{
		sessions: make(map[string]*Session), max: max, shell: shell,
		dataDir: dataDir, executable: executable, pendingKeys: make(map[string]pendingHostKey),
	}, nil
}

func (m *Manager) StartShell(ctx context.Context, id string) (*Session, error) {
	command := exec.CommandContext(ctx, m.shell, "-l")
	command.Env = append(os.Environ(), "TERM=xterm-256color", "COLORTERM=truecolor")
	return m.start(id, "shell", "Local Shell", command)
}

func (m *Manager) StartSSH(ctx context.Context, id string, connection vault.Connection) (*Session, error) {
	target := connection.Host
	if connection.Credential.Username != "" {
		target = connection.Credential.Username + "@" + target
	}
	knownHosts := filepath.Join(m.dataDir, "known_hosts")
	args := []string{
		"-tt", "-p", strconv.Itoa(connection.Port),
		"-o", "ConnectTimeout=10",
		"-o", "ServerAliveInterval=30",
		"-o", "ServerAliveCountMax=3",
		"-o", "StrictHostKeyChecking=yes",
		"-o", "UserKnownHostsFile=" + knownHosts,
		target,
	}
	command := exec.CommandContext(ctx, "ssh", args...)
	command.Env = append(os.Environ(), "TERM=xterm-256color", "COLORTERM=truecolor")
	password := connection.Credential.Password
	var cancelAskpass func()
	if password != "" {
		socketPath, cancel, err := m.prepareAskpass(password)
		if err != nil {
			return nil, err
		}
		cancelAskpass = cancel
		command.Env = append(command.Env,
			"SSH_ASKPASS="+m.executable,
			"SSH_ASKPASS_REQUIRE=force",
			"DISPLAY=myshell",
			"MYSHELL_ASKPASS_SOCKET="+socketPath,
		)
	}
	session, err := m.start(id, "ssh", connection.Name, command)
	if err != nil && cancelAskpass != nil {
		cancelAskpass()
	}
	return session, err
}

func (m *Manager) prepareAskpass(password string) (string, func(), error) {
	runDir := filepath.Join(m.dataDir, "run")
	if err := os.MkdirAll(runDir, 0o700); err != nil {
		return "", nil, err
	}
	random := make([]byte, 12)
	if _, err := rand.Read(random); err != nil {
		return "", nil, err
	}
	socketPath := filepath.Join(runDir, "askpass-"+hex.EncodeToString(random)+".sock")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		return "", nil, err
	}
	if err := os.Chmod(socketPath, 0o600); err != nil {
		listener.Close()
		os.Remove(socketPath)
		return "", nil, err
	}
	var once sync.Once
	cancel := func() {
		once.Do(func() {
			_ = listener.Close()
			_ = os.Remove(socketPath)
		})
	}
	go func() {
		defer cancel()
		_ = listener.SetDeadline(time.Now().Add(30 * time.Second))
		connection, err := listener.AcceptUnix()
		if err != nil {
			return
		}
		_ = connection.SetWriteDeadline(time.Now().Add(3 * time.Second))
		_, _ = io.WriteString(connection, password+"\n")
		_ = connection.Close()
	}()
	return socketPath, cancel, nil
}

func (m *Manager) HostKey(ctx context.Context, connection vault.Connection) (HostKeyStatus, error) {
	hostSpec := connection.Host
	if connection.Port != 22 {
		hostSpec = "[" + connection.Host + "]:" + strconv.Itoa(connection.Port)
	}
	knownHosts := filepath.Join(m.dataDir, "known_hosts")
	find := exec.CommandContext(ctx, "ssh-keygen", "-F", hostSpec, "-f", knownHosts)
	if err := find.Run(); err == nil {
		return HostKeyStatus{Trusted: true}, nil
	}
	scanCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	scan := exec.CommandContext(scanCtx, "ssh-keyscan", "-T", "5", "-p", strconv.Itoa(connection.Port), connection.Host)
	output, err := scan.Output()
	if err != nil || len(output) == 0 {
		return HostKeyStatus{}, errors.New("unable to retrieve SSH host key")
	}
	var line string
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		candidate := strings.TrimSpace(scanner.Text())
		if candidate != "" && !strings.HasPrefix(candidate, "#") {
			line = candidate
			break
		}
	}
	if line == "" {
		return HostKeyStatus{}, errors.New("SSH host did not provide a key")
	}
	fingerprintCommand := exec.CommandContext(ctx, "ssh-keygen", "-lf", "-")
	fingerprintCommand.Stdin = strings.NewReader(line + "\n")
	fingerprintOutput, err := fingerprintCommand.Output()
	if err != nil {
		return HostKeyStatus{}, errors.New("unable to calculate SSH host fingerprint")
	}
	fields := strings.Fields(string(fingerprintOutput))
	if len(fields) < 4 {
		return HostKeyStatus{}, errors.New("SSH host fingerprint output is invalid")
	}
	status := HostKeyStatus{Fingerprint: fields[1], Algorithm: strings.Trim(fields[3], "()")}
	m.hostKeyMu.Lock()
	m.pendingKeys[connection.ID] = pendingHostKey{
		line: line, fingerprint: status.Fingerprint, expiresAt: time.Now().Add(5 * time.Minute),
	}
	m.hostKeyMu.Unlock()
	return status, nil
}

func (m *Manager) TrustHostKey(connectionID, fingerprint string) error {
	m.hostKeyMu.Lock()
	defer m.hostKeyMu.Unlock()
	pending, ok := m.pendingKeys[connectionID]
	if !ok || time.Now().After(pending.expiresAt) || pending.fingerprint != fingerprint {
		delete(m.pendingKeys, connectionID)
		return errors.New("host key confirmation expired; scan again")
	}
	path := filepath.Join(m.dataDir, "known_hosts")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	_, writeErr := io.WriteString(file, pending.line+"\n")
	syncErr := file.Sync()
	closeErr := file.Close()
	delete(m.pendingKeys, connectionID)
	if writeErr != nil {
		return writeErr
	}
	if syncErr != nil {
		return syncErr
	}
	return closeErr
}

func (m *Manager) start(id, kind, label string, command *exec.Cmd) (*Session, error) {
	m.mu.Lock()
	if len(m.sessions)+m.starting >= m.max {
		m.mu.Unlock()
		return nil, ErrLimit
	}
	if _, exists := m.sessions[id]; exists {
		m.mu.Unlock()
		return nil, errors.New("terminal id already exists")
	}
	m.starting++
	m.mu.Unlock()

	ptmx, err := pty.StartWithSize(command, &pty.Winsize{Rows: 30, Cols: 100})
	if err != nil {
		m.mu.Lock()
		m.starting--
		m.mu.Unlock()
		return nil, fmt.Errorf("start terminal: %w", err)
	}
	session := &Session{
		ID: id, Kind: kind, Label: label, CreatedAt: time.Now().UTC(),
		ptmx: ptmx, command: command, done: make(chan struct{}),
	}
	m.mu.Lock()
	m.starting--
	m.sessions[id] = session
	m.mu.Unlock()
	go func() {
		_ = command.Wait()
		session.close()
		m.mu.Lock()
		delete(m.sessions, id)
		m.mu.Unlock()
	}()
	return session, nil
}

func (m *Manager) Get(id string) (*Session, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	session, ok := m.sessions[id]
	return session, ok
}

func (m *Manager) List() []Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	result := make([]Session, 0, len(m.sessions))
	for _, session := range m.sessions {
		result = append(result, Session{
			ID: session.ID, Kind: session.Kind, Label: session.Label, CreatedAt: session.CreatedAt,
		})
	}
	return result
}

func (m *Manager) Resize(id string, rows, cols uint16) error {
	if rows < 2 || cols < 2 || rows > 500 || cols > 1000 {
		return ErrInvalidSize
	}
	session, ok := m.Get(id)
	if !ok {
		return ErrNotFound
	}
	session.mu.Lock()
	defer session.mu.Unlock()
	return pty.Setsize(session.ptmx, &pty.Winsize{Rows: rows, Cols: cols})
}

func (m *Manager) Close(id string) error {
	session, ok := m.Get(id)
	if !ok {
		return ErrNotFound
	}
	session.close()
	m.mu.Lock()
	delete(m.sessions, id)
	m.mu.Unlock()
	return nil
}

func (m *Manager) CloseAll() {
	m.mu.Lock()
	sessions := make([]*Session, 0, len(m.sessions))
	for _, session := range m.sessions {
		sessions = append(sessions, session)
	}
	m.mu.Unlock()
	for _, session := range sessions {
		session.close()
	}
}

func (s *Session) Read(buffer []byte) (int, error) {
	s.mu.Lock()
	file := s.ptmx
	s.mu.Unlock()
	if file == nil {
		return 0, io.EOF
	}
	return file.Read(buffer)
}

func (s *Session) Write(buffer []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ptmx == nil {
		return 0, io.ErrClosedPipe
	}
	return s.ptmx.Write(buffer)
}

func (s *Session) Done() <-chan struct{} {
	return s.done
}

func (s *Session) close() {
	s.once.Do(func() {
		s.mu.Lock()
		if s.ptmx != nil {
			_ = s.ptmx.Close()
			s.ptmx = nil
		}
		if s.command != nil && s.command.Process != nil {
			_ = syscall.Kill(-s.command.Process.Pid, syscall.SIGTERM)
			go func(pid int) {
				timer := time.NewTimer(2 * time.Second)
				defer timer.Stop()
				<-timer.C
				_ = syscall.Kill(-pid, syscall.SIGKILL)
			}(s.command.Process.Pid)
		}
		s.mu.Unlock()
		close(s.done)
	})
}
