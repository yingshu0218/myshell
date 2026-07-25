# Repository Guidelines

## Scope

MyShell is a monorepo with three independent clients:

- `web/` — Docker-hosted browser terminal.
- `macos/` — native Swift macOS client.
- `windows/` — native Windows client.

Shared schemas, encryption-envelope specifications, and cross-language test
vectors belong in `shared/`. Do not share UI implementations or package one
client inside another. Sync Hub is a separate service and repository; MyShell
uses only its documented HTTPS API.

## Mandatory Startup Sequence

Before changing files, read in full:

1. This `AGENTS.md`.
2. Root `README.md`.
3. `docs/PROJECT_OVERVIEW.md`.
4. `docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md`.
5. `shared/README.md`.
6. `shared/COMPATIBILITY.md`.
7. The README and `DEVELOPMENT.md` inside the target client directory.
8. Relevant source, persistence, security, network, and test code.

Then report the observed state, intended file scope, contract conflicts,
dependency or migration needs, and a testable rollback-safe plan. Do not begin
implementation while a product, security, or irreversible data decision is
unresolved.

## Delivery Order and Boundaries

Finish shared schema, encryption, and test-vector decisions before client
integration. Current implementation order is Web, macOS, then Windows. A task
normally changes only one client directory. Cross-client behavior changes must
also update `shared/` specifications and compatibility tests.

Client work follows the numbered gates in its `DEVELOPMENT.md`. Advance one
gate at a time and report its files, tests, security impact, resource evidence,
and rollback path before starting the next gate.

Never add MyShell-specific fields to Sync Hub. Do not access Sync Hub storage
directly. Validate behavior against Sync Hub baseline commit
`7b5038c15fb87158de4bbd43d7fb510c7a52521e`.

## Security

Sync only client-encrypted, authenticated credentials. Never sync or log
plaintext passwords, SSH private keys, terminal content, tokens, vault keys,
recovery keys, cookies, or live-session data. Store platform secrets in Docker
Secrets, macOS Keychain, or Windows secure credential storage as documented.
Keep TLS certificate validation enabled.

Use bounded buffers, queues, retries, sessions, history, concurrency, and
network timeouts. Closing a terminal must release its process, PTY, descriptors,
and memory. Resource usage is an acceptance criterion on every platform.

## Dependencies and Changes

Third-party dependencies require the repository owner's explicit approval
before manifest edits, downloads, copied source, or dependent implementation.
Approval is package- and purpose-specific. Explain the alternative, license,
size, runtime cost, and maintenance risk.

Do not perform unapproved migrations, destructive operations, protocol
extensions, or broad cross-client refactors. Keep commits focused and
imperative. Never commit build output, runtime data, credentials, or local IDE
state.

## Verification

Use the real commands documented by the target client. Verify relevant unit,
integration, security, build, container/application, and performance behavior.
Do not invent root commands before they exist, and do not claim completion from
code inspection alone.

Do not use any Superpowers skill in this repository.
