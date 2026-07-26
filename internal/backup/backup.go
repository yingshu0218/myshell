package backup

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"
	"time"

	"github.com/yingshu0218/myshell/internal/vault"
)

type Item struct {
	Name string `json:"name"`
	Path string `json:"path"`
	SHA  string `json:"sha"`
	Size int64  `json:"size"`
}

type Manager struct {
	client    *http.Client
	tokenFile string
}

func New(tokenFile string) *Manager {
	return &Manager{
		client:    &http.Client{Timeout: 15 * time.Second},
		tokenFile: tokenFile,
	}
}

func (m *Manager) Save(ctx context.Context, config vault.BackupConfig, envelope vault.Envelope) (Item, error) {
	if err := validate(config); err != nil {
		return Item{}, err
	}
	token, err := m.token()
	if err != nil {
		return Item{}, err
	}
	payload, err := json.Marshal(envelope)
	if err != nil {
		return Item{}, err
	}
	name := fmt.Sprintf("vault-%s-v%d.json", time.Now().UTC().Format("20060102T150405.000000000Z"), envelope.Version)
	remotePath := "backups/" + name
	endpoint, err := contentURL(config, remotePath, false)
	if err != nil {
		return Item{}, err
	}
	body := map[string]string{
		"message": "Back up MyShell encrypted vault",
		"content": base64.StdEncoding.EncodeToString(payload),
		"branch":  config.Branch,
	}
	method := http.MethodPost
	if config.Provider == "github" {
		method = http.MethodPut
	}
	response, err := m.request(ctx, config, token, method, endpoint, body)
	if err != nil {
		return Item{}, err
	}
	_ = response
	return Item{Name: name, Path: remotePath, Size: int64(len(payload))}, nil
}

func (m *Manager) List(ctx context.Context, config vault.BackupConfig) ([]Item, error) {
	if err := validate(config); err != nil {
		return nil, err
	}
	token, err := m.token()
	if err != nil {
		return nil, err
	}
	endpoint, err := contentURL(config, "backups", true)
	if err != nil {
		return nil, err
	}
	var items []Item
	if err := m.get(ctx, config, token, endpoint, &items); err != nil {
		if strings.Contains(err.Error(), "404") {
			return []Item{}, nil
		}
		return nil, err
	}
	result := items[:0]
	for _, item := range items {
		if strings.HasPrefix(item.Name, "vault-") && strings.HasSuffix(item.Name, ".json") {
			result = append(result, item)
		}
	}
	return result, nil
}

func (m *Manager) Load(ctx context.Context, config vault.BackupConfig, remotePath string) (vault.Envelope, error) {
	if err := validate(config); err != nil {
		return vault.Envelope{}, err
	}
	clean := path.Clean("/" + remotePath)
	if !strings.HasPrefix(clean, "/backups/vault-") || !strings.HasSuffix(clean, ".json") {
		return vault.Envelope{}, errors.New("invalid backup path")
	}
	token, err := m.token()
	if err != nil {
		return vault.Envelope{}, err
	}
	endpoint, err := contentURL(config, strings.TrimPrefix(clean, "/"), true)
	if err != nil {
		return vault.Envelope{}, err
	}
	var file struct {
		Content string `json:"content"`
	}
	if err := m.get(ctx, config, token, endpoint, &file); err != nil {
		return vault.Envelope{}, err
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(file.Content, "\n", ""))
	if err != nil {
		return vault.Envelope{}, errors.New("backup content is invalid")
	}
	var envelope vault.Envelope
	if err := json.Unmarshal(decoded, &envelope); err != nil {
		return vault.Envelope{}, errors.New("backup envelope is invalid")
	}
	return envelope, nil
}

func (m *Manager) token() (string, error) {
	data, err := os.ReadFile(m.tokenFile)
	if err != nil {
		return "", fmt.Errorf("read git token secret: %w", err)
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return "", errors.New("git token secret is empty")
	}
	return token, nil
}

func (m *Manager) get(ctx context.Context, config vault.BackupConfig, token, endpoint string, target any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	setHeaders(request, config, token)
	response, err := m.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return fmt.Errorf("backup provider returned %d", response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(target)
}

func (m *Manager) request(ctx context.Context, config vault.BackupConfig, token, method, endpoint string, body any) (map[string]any, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	setHeaders(request, config, token)
	request.Header.Set("Content-Type", "application/json")
	response, err := m.client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return nil, fmt.Errorf("backup provider returned %d", response.StatusCode)
	}
	result := make(map[string]any)
	_ = json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(&result)
	return result, nil
}

func setHeaders(request *http.Request, config vault.BackupConfig, token string) {
	request.Header.Set("Accept", "application/json")
	if config.Provider == "github" {
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	} else {
		request.Header.Set("Authorization", "token "+token)
	}
}

func contentURL(config vault.BackupConfig, filePath string, includeRef bool) (string, error) {
	base := strings.TrimRight(config.APIBase, "/")
	if base == "" {
		if config.Provider == "github" {
			base = "https://api.github.com"
		} else {
			return "", errors.New("gitea api base is required")
		}
	}
	parsed, err := url.Parse(base)
	if err != nil || (parsed.Scheme != "https" && parsed.Scheme != "http") {
		return "", errors.New("backup api base is invalid")
	}
	if parsed.Scheme == "http" && parsed.Hostname() != "localhost" &&
		parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "::1" {
		return "", errors.New("backup api base must use HTTPS")
	}
	parsed.Path = strings.TrimRight(parsed.Path, "/") + "/repos/" +
		url.PathEscape(config.Owner) + "/" + url.PathEscape(config.Repo) +
		"/contents/" + strings.TrimLeft(filePath, "/")
	if includeRef {
		query := parsed.Query()
		query.Set("ref", config.Branch)
		parsed.RawQuery = query.Encode()
	}
	return parsed.String(), nil
}

func validate(config vault.BackupConfig) error {
	if !config.Enabled {
		return errors.New("backup is disabled")
	}
	if config.Provider != "github" && config.Provider != "gitea" {
		return errors.New("unsupported backup provider")
	}
	if config.Owner == "" || config.Repo == "" || config.Branch == "" {
		return errors.New("backup repository configuration is incomplete")
	}
	return nil
}
