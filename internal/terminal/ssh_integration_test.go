package terminal

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/yingshu0218/myshell/internal/vault"
)

func TestSystemSSHPasswordRoundTripAndDisconnect(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("SSH integration test requires root inside the disposable test container")
	}
	for _, command := range []string{"sshd", "ssh", "ssh-keyscan", "ssh-keygen", "adduser", "chpasswd"} {
		if _, err := exec.LookPath(command); err != nil {
			t.Skipf("%s is unavailable", command)
		}
	}
	sshdPath, _ := exec.LookPath("sshd")
	directory := t.TempDir()
	if err := os.Chmod(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	username := "myshelltest" + strconv.Itoa(os.Getpid())
	home := filepath.Join(directory, "home")
	if output, err := exec.Command("adduser", "-D", "-h", home, username).CombinedOutput(); err != nil {
		t.Fatalf("add test user: %v: %s", err, output)
	}
	t.Cleanup(func() { _ = exec.Command("deluser", username).Run() })
	passwordCommand := exec.Command("chpasswd")
	passwordCommand.Stdin = strings.NewReader(username + ":111111\n")
	if output, err := passwordCommand.CombinedOutput(); err != nil {
		t.Fatalf("set test password: %v: %s", err, output)
	}
	hostKey := filepath.Join(directory, "ssh_host_ed25519_key")
	if output, err := exec.Command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", hostKey).CombinedOutput(); err != nil {
		t.Fatalf("create host key: %v: %s", err, output)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	_, portText, _ := net.SplitHostPort(listener.Addr().String())
	listener.Close()
	port, _ := strconv.Atoi(portText)
	configPath := filepath.Join(directory, "sshd_config")
	config := fmt.Sprintf(`Port %d
ListenAddress 127.0.0.1
HostKey %s
PidFile %s
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers %s
StrictModes no
`, port, hostKey, filepath.Join(directory, "sshd.pid"), username)
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll("/run/sshd", 0o755); err != nil {
		t.Fatal(err)
	}
	sshd := exec.Command(sshdPath, "-D", "-e", "-f", configPath)
	var sshdLog bytes.Buffer
	sshd.Stderr = &sshdLog
	sshd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := sshd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = syscall.Kill(-sshd.Process.Pid, syscall.SIGTERM)
		_ = sshd.Wait()
	})
	waitForSSHPort(t, port, &sshdLog)

	manager, err := New(1, "/bin/sh", directory)
	if err != nil {
		t.Fatal(err)
	}
	serverBinary := filepath.Join(directory, "myshell-server")
	build := exec.Command("go", "build", "-o", serverBinary, "github.com/yingshu0218/myshell/cmd/server")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build production AskPass binary: %v: %s", err, output)
	}
	manager.executable = serverBinary
	defer manager.CloseAll()
	connection := vault.Connection{
		ID: "ssh-test", Name: "SSH integration", Host: "127.0.0.1", Port: port,
		Credential: vault.Credential{Username: username, Password: "111111"},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	hostStatus, err := manager.HostKey(ctx, connection)
	if err != nil {
		t.Fatalf("scan host key: %v; sshd=%s", err, sshdLog.String())
	}
	if hostStatus.Trusted || hostStatus.Fingerprint == "" {
		t.Fatalf("unexpected first host status: %+v", hostStatus)
	}
	if err := manager.TrustHostKey(connection.ID, hostStatus.Fingerprint); err != nil {
		t.Fatal(err)
	}
	session, err := manager.StartSSH(ctx, "ssh-session", connection)
	if err != nil {
		t.Fatalf("start SSH: %v; sshd=%s", err, sshdLog.String())
	}
	if _, err := session.Write([]byte("printf 'myshell-ssh-ok\\n'\nexit\n")); err != nil {
		t.Fatal(err)
	}
	output := make(chan string, 1)
	go func() {
		var buffer bytes.Buffer
		_, _ = io.Copy(&buffer, session)
		output <- buffer.String()
	}()
	select {
	case text := <-output:
		if !strings.Contains(text, "myshell-ssh-ok") {
			t.Fatalf("SSH output = %q; sshd=%s", text, sshdLog.String())
		}
	case <-ctx.Done():
		t.Fatalf("SSH round trip timed out; sshd=%s", sshdLog.String())
	}
	select {
	case <-session.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("SSH disconnect did not clean up the terminal session")
	}
}

func waitForSSHPort(t *testing.T, port int, log *bytes.Buffer) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	address := net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	for time.Now().Before(deadline) {
		connection, err := net.DialTimeout("tcp", address, 100*time.Millisecond)
		if err == nil {
			connection.Close()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("sshd did not listen on %s: %s", address, log.String())
}
