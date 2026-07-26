package terminal

import (
	"bytes"
	"context"
	"io"
	"net"
	"os"
	"strings"
	"testing"
	"time"
)

func TestShellLifecycle(t *testing.T) {
	manager, err := New(1, "/bin/sh", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer manager.CloseAll()
	session, err := manager.StartShell(context.Background(), "test")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := session.Write([]byte("printf 'myshell-pty-ok\\n'\nexit\n")); err != nil {
		t.Fatal(err)
	}
	output := make(chan string, 1)
	go func() {
		var buffer bytes.Buffer
		_, _ = io.Copy(&buffer, session)
		output <- buffer.String()
	}()
	select {
	case value := <-output:
		if !strings.Contains(value, "myshell-pty-ok") {
			t.Fatalf("terminal output = %q", value)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("terminal did not exit")
	}
	select {
	case <-session.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("terminal resources were not cleaned up")
	}
}

func TestTerminalLimit(t *testing.T) {
	manager, err := New(1, "/bin/sh", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer manager.CloseAll()
	if _, err := manager.StartShell(context.Background(), "one"); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.StartShell(context.Background(), "two"); err != ErrLimit {
		t.Fatalf("error = %v, want terminal limit", err)
	}
}

func TestAskpassUsesOneTimeProtectedSocket(t *testing.T) {
	manager, err := New(1, "/bin/sh", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	socketPath, cancel, err := manager.prepareAskpass("one-time-password")
	if err != nil {
		t.Fatal(err)
	}
	defer cancel()
	info, err := os.Stat(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("socket mode = %o, want 600", info.Mode().Perm())
	}
	connection, err := net.DialTimeout("unix", socketPath, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	secret, err := io.ReadAll(connection)
	connection.Close()
	if err != nil {
		t.Fatal(err)
	}
	if string(secret) != "one-time-password\n" {
		t.Fatalf("secret = %q", secret)
	}
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(socketPath); os.IsNotExist(err) {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("askpass socket was not removed after one read")
}
