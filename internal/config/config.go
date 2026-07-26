package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Address            string
	DataDir            string
	Shell              string
	PublicURL          string
	SecureCookies      bool
	SessionIdle        time.Duration
	SessionAbsolute    time.Duration
	MaxTerminals       int
	MaxHealthChecks    int
	HealthTimeout      time.Duration
	VaultKeyFile       string
	GitTokenFile       string
	AllowTestBootstrap bool
	TestUsername       string
	TestPassword       string
}

func Load() (Config, error) {
	cfg := Config{
		Address:         env("MYSHELL_ADDRESS", ":8080"),
		DataDir:         env("MYSHELL_DATA_DIR", "./data"),
		Shell:           env("MYSHELL_SHELL", "/bin/sh"),
		PublicURL:       os.Getenv("MYSHELL_PUBLIC_URL"),
		SecureCookies:   envBool("MYSHELL_SECURE_COOKIES", true),
		SessionIdle:     envDuration("MYSHELL_SESSION_IDLE", 30*time.Minute),
		SessionAbsolute: envDuration("MYSHELL_SESSION_ABSOLUTE", 12*time.Hour),
		MaxTerminals:    envInt("MYSHELL_MAX_TERMINALS", 8),
		MaxHealthChecks: envInt("MYSHELL_MAX_HEALTH_CHECKS", 4),
		HealthTimeout:   envDuration("MYSHELL_HEALTH_TIMEOUT", 3*time.Second),
		VaultKeyFile:    env("MYSHELL_VAULT_KEY_FILE", "/run/secrets/vault_key"),
		GitTokenFile:    env("MYSHELL_GIT_TOKEN_FILE", "/run/secrets/git_token"),
	}
	if os.Getenv("MYSHELL_TEST_BOOTSTRAP") == "1" {
		cfg.AllowTestBootstrap = true
		cfg.TestUsername = os.Getenv("MYSHELL_TEST_USERNAME")
		cfg.TestPassword = os.Getenv("MYSHELL_TEST_PASSWORD")
		if cfg.TestUsername == "" || cfg.TestPassword == "" {
			return Config{}, errors.New("test bootstrap requires MYSHELL_TEST_USERNAME and MYSHELL_TEST_PASSWORD")
		}
	}
	if cfg.MaxTerminals < 1 || cfg.MaxTerminals > 32 {
		return Config{}, errors.New("MYSHELL_MAX_TERMINALS must be between 1 and 32")
	}
	if cfg.MaxHealthChecks < 1 || cfg.MaxHealthChecks > 16 {
		return Config{}, errors.New("MYSHELL_MAX_HEALTH_CHECKS must be between 1 and 16")
	}
	if cfg.SecureCookies && !strings.HasPrefix(cfg.PublicURL, "https://") {
		return Config{}, errors.New("MYSHELL_PUBLIC_URL must use https:// when secure cookies are enabled")
	}
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return Config{}, fmt.Errorf("create data directory: %w", err)
	}
	cfg.DataDir, _ = filepath.Abs(cfg.DataDir)
	return cfg, nil
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func envBool(name string, fallback bool) bool {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envInt(name string, fallback int) int {
	value, err := strconv.Atoi(os.Getenv(name))
	if err != nil {
		return fallback
	}
	return value
}

func envDuration(name string, fallback time.Duration) time.Duration {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}
