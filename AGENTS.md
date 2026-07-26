# Repository Guidelines

## Product Scope and Delivery Order

MyShell has three entry points:

1. A Docker-hosted browser terminal and synchronization service.
2. A native macOS client written in Swift.
3. A native Windows client.

Finish the Docker web terminal and relay first. Do not scaffold macOS or
Windows code until the completion gate in `docs/DEVELOPMENT.md` passes. Clients
use the relay for encrypted synchronization. GitHub and Gitea are optional
encrypted backups, not live synchronization providers.

## Current Web/Relay Architecture

Prefer one Go process with an embedded HTML/CSS/JavaScript frontend in one
container. Organize Go code under `cmd/server/` and `internal/`; keep frontend
sources under `web/`. Use bounded sessions and atomic files before a database.

The service must provide:

- Single-user account/password authentication with no public registration.
- Browser terminal sessions backed by server-side PTY and system SSH.
- Encrypted vault synchronization APIs for future native clients.
- Manual and scheduled relay/SSH-target health checks.
- Optional manual or scheduled encrypted GitHub/Gitea backups.
- A local interactive `reset-password` command that invalidates all sessions.

## Commands and Verification

Expose predictable commands when the Go module is created:

- `go test ./...` — run backend tests.
- `go vet ./...` — run static checks.
- `go build ./cmd/server` — build the service.
- `docker build -t myshell:dev .` — build the container.

Test authentication, session expiry, PTY cleanup, SSH disconnects, vault
versioning, conflicts, health-check limits, backup/restore, and password reset.
Measure binary and container size, startup, idle CPU, baseline and per-terminal
memory, and terminal throughput.

## Security and Resource Rules

Require HTTPS in public deployments. Store password hashes, never plaintext
passwords. Do not place credentials, recovery keys, tokens, or terminal content
in logs, command arguments, images, or ordinary environment variables. Load
the vault recovery key through Docker Secrets. Bound terminal scrollback,
concurrent checks, sessions, retries, and buffers. Avoid polling when no
configured schedule requires it.

## Code and Contribution Rules

Format Go with `gofmt`; use standard Go naming. Keep packages narrow and avoid
global mutable state. Use native browser APIs and accessible semantic HTML.
Keep commits focused and imperative. Pull requests must list tests and relevant
performance measurements. Do not commit binaries, runtime data, secrets, or
local IDE files.

Third-party dependencies require the repository owner's explicit approval
before manifest edits, downloads, copied source, or dependent implementation.
Do not use any Superpowers skill in this repository.
