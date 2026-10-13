# First Release Audit

Audit date: 2026-07-26. Scope: macOS 14+, Apple Silicon only.

## Verified Locally

| Area | Evidence |
| --- | --- |
| Build and tests | Debug run passed: 46 default tests, 0 failures; the opt-in live Sync Hub integration test also passed. Unsigned Release build passed. |
| Platform | Release `Info.plist` reports macOS 14.0, bundle ID `com.yingshu0218.myshell`, version 0.1.0 (1). The final executable contains only `arm64`. |
| Terminal | Native Darwin PTY, `/bin/zsh`, SwiftTerm 1.15.0, tabs, windows, themes, restart, and bounded output are implemented. |
| Connections | SQLite v6 storage, stable UUIDs, tombstones, local dirty tracking, validation, search, JSON import/export, command groups, and reachability checks have automated coverage. |
| Secrets | Token and vault key use separate local, non-synchronizable Keychain items. Child-process environments remove secret-like variables. |
| Sync foundation | Shared v1 schemas, AES-GCM envelope/AAD, recovery format and fixed vectors are published. Connections and non-secret command groups share the real pull/push loop, transactional mixed-page application, persisted 409 conflicts, explicit local/remote choice, bounded queue, and stable idempotency keys. |
| Release baseline | The personal unsigned ZIP and SHA-256 workflow is verified; the executable is arm64. Future Developer ID tooling remains scripted. A 10-second Release smoke sample measured 0.0% CPU and 50,864 KiB RSS. |

Reproduce the main checks:

```bash
cd macos
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/myshell-audit \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/myshell-audit-release \
  CODE_SIGNING_ALLOWED=NO build
```

## External Release Gates

These are not code-complete claims and must pass before publishing:

1. **Cross-client implementation:** Web ↔ macOS interoperability remains; macOS encrypted upload, pull, recovery UI, and conflict persistence are implemented, and a two-device live Sync Hub test passes.
2. **SSH test environment:** provide hosts covering password, key, Agent, unknown/changed fingerprints, timeout, disconnect, and ProxyJump.
3. **Duration and lifecycle testing:** complete Instruments startup measurement, high-throughput and 12-terminal tests, 8-hour idle, 24-hour active session, crash recovery, sleep/wake, and network switching.

Developer ID and notarization are future options rather than first-release gates. Until the
remaining gates pass, M4, M6, M7, and M8 remain partially accepted.
