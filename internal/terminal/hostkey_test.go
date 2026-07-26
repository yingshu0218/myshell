package terminal

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestTrustHostKeyRequiresMatchingFreshFingerprint(t *testing.T) {
	directory := t.TempDir()
	manager, err := New(1, "/bin/sh", directory)
	if err != nil {
		t.Fatal(err)
	}
	manager.pendingKeys["server"] = pendingHostKey{
		line:        "example.test ssh-ed25519 AAAATEST",
		fingerprint: "SHA256:expected", expiresAt: time.Now().Add(time.Minute),
	}
	if err := manager.TrustHostKey("server", "SHA256:wrong"); err == nil {
		t.Fatal("mismatched fingerprint was trusted")
	}
	manager.pendingKeys["server"] = pendingHostKey{
		line:        "example.test ssh-ed25519 AAAATEST",
		fingerprint: "SHA256:expected", expiresAt: time.Now().Add(time.Minute),
	}
	if err := manager.TrustHostKey("server", "SHA256:expected"); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(filepath.Join(directory, "known_hosts"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), "ssh-ed25519 AAAATEST") {
		t.Fatalf("known_hosts = %q", content)
	}
}
