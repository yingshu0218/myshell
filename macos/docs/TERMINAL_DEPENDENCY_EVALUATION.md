# Terminal Rendering Dependency Evaluation

## Decision

状态：已批准并接入（2026-07-26）。

M3 needs a production-quality Xterm/VT100 parser and native macOS renderer. The
recommended dependency is:

- Package: `SwiftTerm`
- Repository: `https://github.com/migueldeicaza/SwiftTerm`
- Proposed version: exact tag `v1.15.0`
- License: MIT
- Product used: library product `SwiftTerm`
- Purpose: ANSI/VT parsing, Unicode terminal grid, AppKit rendering, selection,
  keyboard/mouse input, resize, colors and accessibility-related terminal behavior

`Package.swift` 与 Xcode 工程均精确锁定 `v1.15.0`；解析结果记录在
`Package.resolved`。应用只链接 `SwiftTerm` library product。

## Why this is recommended

SwiftTerm provides an AppKit `TerminalView` plus a UI-independent terminal
engine. Its documented features cover ANSI, 256/true color, Unicode and
grapheme rendering, text attributes, mouse reporting, selection, search,
resize and hardened terminal parser testing.

MyShell would continue to own the Darwin PTY and process lifecycle. SwiftTerm
would receive PTY output and return user input through a narrow adapter; its
`LocalProcessTerminalView` would not replace MyShell's bounded session service.
This keeps process cleanup, logging and future SSH integration under MyShell
control.

## Dependency and resource impact

The `SwiftTerm` library target has no direct target dependency at `v1.15.0`.
The package manifest also declares Apple `swift-argument-parser` and
`swift-docc-plugin` for other products/tooling, so Swift Package resolution may
download them even though MyShell does not link their products.

Expected runtime cost is the SwiftTerm library, AppKit/CoreText rendering and
its packaged Metal shader. Exact application size, cold start, idle CPU,
baseline RSS and per-session RSS must be measured in Release after integration.
The dependency is rejected if it prevents the approved M8 resource targets
without an accepted exception.

## Alternatives

### Implement the emulator in MyShell

This avoids an external package but requires independently implementing and
maintaining escape parsing, alternate screen buffers, Unicode grapheme width,
selection, IME, mouse protocols, accessibility, color modes and rendering.
It has the highest schedule and correctness risk, especially for Vim, Top and
full-screen remote applications.

### Use a Web terminal

Rejected. Embedding xterm.js or another browser renderer would violate the
native-client and no-WebView requirements.

### Use libghostty or another non-Swift engine

Potentially higher performance, but adds a larger foreign-language build,
packaging and signing surface. It is not recommended for the first version
without evidence that SwiftTerm misses a measured requirement.

## Approved scope

批准范围仅包括：

1. Adding the exact `SwiftTerm` `v1.15.0` package.
2. Linking only the `SwiftTerm` library product in the macOS client.
3. Building a narrow adapter between `PTYSession` and `TerminalView`.
4. Including the required MIT attribution.

It would not approve an SSH library, updater, analytics package, or any other
dependency.
