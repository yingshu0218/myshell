package config

import (
	"strings"
	"testing"
)

func TestSecureModeRequiresHTTPSPublicURL(t *testing.T) {
	t.Setenv("MYSHELL_DATA_DIR", t.TempDir())
	t.Setenv("MYSHELL_SECURE_COOKIES", "true")
	t.Setenv("MYSHELL_PUBLIC_URL", "http://shell.example.test")
	if _, err := Load(); err == nil || !strings.Contains(err.Error(), "https://") {
		t.Fatalf("error = %v", err)
	}
}

func TestDevelopmentHTTPMustBeExplicit(t *testing.T) {
	t.Setenv("MYSHELL_DATA_DIR", t.TempDir())
	t.Setenv("MYSHELL_SECURE_COOKIES", "false")
	t.Setenv("MYSHELL_PUBLIC_URL", "")
	config, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if config.SecureCookies {
		t.Fatal("development HTTP override was ignored")
	}
}

func TestTestBootstrapDefaultsToRequestedCredentials(t *testing.T) {
	t.Setenv("MYSHELL_DATA_DIR", t.TempDir())
	t.Setenv("MYSHELL_SECURE_COOKIES", "false")
	t.Setenv("MYSHELL_TEST_BOOTSTRAP", "1")
	t.Setenv("MYSHELL_TEST_USERNAME", "111111")
	t.Setenv("MYSHELL_TEST_PASSWORD", "111111")
	config, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if config.TestUsername != "111111" || config.TestPassword != "111111" {
		t.Fatalf("test credentials = %q/%q", config.TestUsername, config.TestPassword)
	}
}
