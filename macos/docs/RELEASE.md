# macOS Release

The first release is an Apple Silicon-only personal-use build distributed through
local builds, GitHub Releases, or Homebrew. There is currently no Apple Developer
account, so Developer ID signing and notarization are explicitly deferred. GitHub
and Homebrew are delivery channels, not substitutes for Apple trust; a downloaded
unsigned build can require manual Gatekeeper confirmation.

The Release configuration still enables Hardened Runtime and the future signed
release workflow remains available below.

## Current Personal Build

```bash
cd macos
./script/release.sh personal
```

This creates `dist/MyShell-macOS-arm64.zip` and its `.sha256` file. A GitHub
Release or Homebrew recipe must pin both version and checksum and clearly label
the artifact as unsigned. Do not publish instructions that globally disable
Gatekeeper.

## Future Developer ID Release

- A `Developer ID Application` certificate installed in the signing Keychain
- The Apple Developer team identifier
- A `notarytool` Keychain profile created with `xcrun notarytool store-credentials`

Never put certificate material, Apple credentials, or profile passwords in this
repository.

## Archive, Notarize, and Verify

```bash
cd macos
DEVELOPMENT_TEAM=TEAMID ./script/release.sh archive
NOTARY_KEYCHAIN_PROFILE=myshell-notary ./script/release.sh notarize
./script/release.sh verify
```

The script creates `dist/MyShell.xcarchive` and
`dist/MyShell-macOS-arm64.zip`. Verification checks the nested signatures,
Hardened Runtime signing state, Gatekeeper assessment, and that the executable
contains only `arm64`. Notarization is submitted before stapling; the final ZIP
is recreated after stapling so the distributed artifact contains the ticket.

Before publishing, install the ZIP on a clean macOS 14+ Apple Silicon Mac and
verify first launch, local shell, SSH, Keychain access, upgrade, and rollback.
