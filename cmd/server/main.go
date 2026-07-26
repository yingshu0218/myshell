package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/yingshu0218/myshell/internal/auth"
	"github.com/yingshu0218/myshell/internal/config"
	"github.com/yingshu0218/myshell/internal/httpapp"
	"github.com/yingshu0218/myshell/internal/terminal"
	"github.com/yingshu0218/myshell/internal/vault"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "myshell:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	command := "serve"
	if len(arguments) > 0 {
		command = arguments[0]
	}
	if command == "askpass" || os.Getenv("MYSHELL_ASKPASS_SOCKET") != "" {
		return runAskpass()
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	authManager, err := auth.New(cfg.DataDir, cfg.SessionIdle, cfg.SessionAbsolute)
	if err != nil {
		return err
	}
	switch command {
	case "serve":
		return serve(cfg, authManager)
	case "reset-password":
		return resetPassword(authManager)
	case "show-account":
		username, err := authManager.Username()
		if err != nil {
			return err
		}
		fmt.Println(username)
		return nil
	default:
		return fmt.Errorf("unknown command %q (use serve, reset-password or show-account)", command)
	}
}

func serve(cfg config.Config, authManager *auth.Manager) error {
	if cfg.AllowTestBootstrap && !authManager.Initialized() {
		if err := authManager.Initialize(cfg.TestUsername, cfg.TestPassword); err != nil {
			return fmt.Errorf("test bootstrap: %w", err)
		}
	}
	dataVault, err := vault.Open(cfg.DataDir, cfg.VaultKeyFile)
	if err != nil {
		return err
	}
	terminalManager, err := terminal.New(cfg.MaxTerminals, cfg.Shell, cfg.DataDir)
	if err != nil {
		return err
	}
	defer terminalManager.CloseAll()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	app, err := httpapp.New(cfg, authManager, dataVault, terminalManager, logger)
	if err != nil {
		return err
	}
	server := &http.Server{
		Addr: cfg.Address, Handler: app.Handler(),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second,
		WriteTimeout: 0, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 1 << 20,
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go app.RunBackground(ctx)
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		terminalManager.CloseAll()
		_ = server.Shutdown(shutdownCtx)
	}()
	logger.Info("server starting", "address", cfg.Address)
	err = server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func resetPassword(manager *auth.Manager) error {
	first, err := promptPassword("New password: ")
	if err != nil {
		return err
	}
	second, err := promptPassword("Repeat password: ")
	if err != nil {
		return err
	}
	if first != second {
		return errors.New("passwords do not match")
	}
	if err := manager.ResetPassword(first); err != nil {
		return err
	}
	fmt.Println("Password reset; all sessions have been invalidated.")
	return nil
}

func promptPassword(prompt string) (string, error) {
	stateCommand := exec.Command("stty", "-g")
	stateCommand.Stdin = os.Stdin
	state, err := stateCommand.Output()
	if err != nil {
		return "", errors.New("password reset requires an interactive terminal")
	}
	fmt.Fprint(os.Stderr, prompt)
	disableEcho := exec.Command("stty", "-echo")
	disableEcho.Stdin = os.Stdin
	if err := disableEcho.Run(); err != nil {
		return "", errors.New("unable to disable terminal echo")
	}
	defer func() {
		restore := exec.Command("stty", strings.TrimSpace(string(state)))
		restore.Stdin = os.Stdin
		_ = restore.Run()
		fmt.Fprintln(os.Stderr)
	}()
	reader := bufio.NewReader(io.LimitReader(os.Stdin, 4097))
	value, err := reader.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	return strings.TrimRight(value, "\r\n"), nil
}

func runAskpass() error {
	socketPath := os.Getenv("MYSHELL_ASKPASS_SOCKET")
	if socketPath == "" {
		return errors.New("askpass socket is unavailable")
	}
	connection, err := net.DialTimeout("unix", socketPath, 3*time.Second)
	if err != nil {
		return errors.New("askpass socket connection failed")
	}
	defer connection.Close()
	secret, err := io.ReadAll(io.LimitReader(connection, 4096))
	if err != nil {
		return err
	}
	_, err = os.Stdout.Write(secret)
	return err
}
