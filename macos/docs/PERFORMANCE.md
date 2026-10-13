# Performance Verification

Performance claims must use an optimized arm64 Release build. Build first, then
run the repeatable smoke sample:

```bash
cd macos
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/myshell-release \
  CODE_SIGNING_ALLOWED=NO build
SAMPLE_SECONDS=10 ./script/performance_smoke.sh
```

The script launches the Release executable, waits for stabilization, records CPU,
RSS, elapsed time, and child processes, then terminates only that launch. Record
hardware, macOS, Xcode, commit, and sample duration with every result.

The repeatable first-stage scenarios are:

```bash
# No-terminal and 1/4/12-terminal idle matrix.
APP_PATH=/private/tmp/myshell-phase1-release/Build/Products/Release/MyShell.app \
  SAMPLE_SECONDS=10 ./script/performance_smoke.sh matrix

# Feed 32 MiB through the selected terminal using the normal PTY and renderer.
APP_PATH=/private/tmp/myshell-phase1-release/Build/Products/Release/MyShell.app \
  SAMPLE_SECONDS=10 ./script/performance_smoke.sh throughput

# Change the selected tab every 100 ms.
APP_PATH=/private/tmp/myshell-phase1-release/Build/Products/Release/MyShell.app \
  SAMPLE_SECONDS=10 ./script/performance_smoke.sh tab-switch

# A/B the same output load with SwiftTerm's optional Metal renderer.
APP_PATH=/private/tmp/myshell-phase1-release/Build/Products/Release/MyShell.app \
  SAMPLE_SECONDS=10 ./script/performance_smoke.sh throughput-metal
```

These launch controls are inactive unless `MYSHELL_PERFORMANCE_MODE=1`, which
the script sets. Counts and output are bounded to 12 terminals and 64 MiB. The
scenario start delay is bounded to 30 seconds. The script also disables macOS
window-state restoration so previous windows do not contaminate the sample.
The normal application still starts one local terminal and does not inject
output or switch tabs.

Before a public first release, also capture an Instruments App Launch trace,
exercise high-throughput output and 12 simultaneous terminals, perform an 8-hour
idle run and a 24-hour active-session run, then verify sleep/wake and network
switching. These long-running gates cannot be replaced by the smoke sample.
Instruments traces can embed the target process environment. Capture and retain
them only from a clean test account or a sanitized launch environment, inspect
them before sharing, and never commit traces to the repository.

## Current Baseline

2026-07-26 smoke sample: MacBook Pro Mac17,2, Apple M5, 16 GB RAM, macOS
26.5.2 (25F84), Xcode 26.6 (17F113). After 10 seconds, the Release process
reported 0.0% CPU and 50,864 KiB RSS. This passes the provisional idle CPU and
base RSS targets for this short sample; startup latency, per-terminal memory,
throughput, and long-duration targets remain unproven until their dedicated runs.

## First-Stage Baseline

2026-07-31 controlled sample: MacBook Pro Mac17,2, Apple M5 (10 cores), 16 GB
RAM, macOS 26.5.2 (25F84), Xcode 26.6 (17F113), source commit `3260983` plus
the uncommitted first-stage measurement changes. Unsigned optimized arm64
Release build; each result uses ten one-second samples. Idle scenarios wait
three seconds after the expected child processes appear. Memory values are
resident KiB reported by `ps`.

| Scenario | Terminals | Child ready | Tree average CPU | Final app CPU | App RSS | Tree peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Idle, no terminal | 0 | 31.5 ms | 0.000% | 0.0% | 100,880 KiB | 101,088 KiB |
| Idle | 1 | 225.5 ms | 0.020% | 0.0% | 109,456 KiB | 115,424 KiB |
| Idle | 4 | 257.9 ms | 0.020% | 0.0% | 110,656 KiB | 134,272 KiB |
| Idle | 12 | 331.9 ms | 1.720% | 0.0% | 98,352 KiB | 215,824 KiB |
| 32 MiB output, CoreGraphics | 1 | 278.3 ms | 67.450% | 0.0% | 237,792 KiB | 276,720 KiB |
| 32 MiB output, Metal | 1 | 183.3 ms | 67.970% | 0.1% | 255,168 KiB | 275,136 KiB |
| Switch among 12 tabs every 100 ms | 12 | 386.7 ms | 19.600% | 18.7% | 115,840 KiB | 218,448 KiB |
| Idle, Metal | 1 | 488.8 ms | 0.080% | 1.6% | 123,872 KiB | 129,952 KiB |

### Findings

- Empty-state app RSS was about 98.5 MiB in this run, above the provisional
  `< 80 MiB` no-session target. It also contradicts the older 50,864 KiB
  single sample, so RSS needs an Instruments/footprint breakdown before making
  an optimization decision.
- Comparing the no-terminal and 12-terminal process-tree peaks gives a rough
  9.3 MiB increment per terminal, below the provisional `< 15 MiB` target.
  This includes the Zsh processes and should not be treated as a precise
  allocation attribution.
- The app itself returned to 0.0% reported CPU after the 32 MiB CoreGraphics
  output completed, but retained about 232 MiB RSS during the sample. The next
  stage should separate the 4 MiB replay buffer, SwiftTerm's 10,000-row
  scrollback, glyph caches, and allocator high-water behavior.
- Switching tabs every 100 ms kept the app near 18.7% CPU. Current SwiftUI
  structure replaces the selected `TerminalSurface`, so repeated view creation
  and replay is the first lifecycle issue to profile.
- SwiftTerm 1.15.0 contains a Metal renderer but disables it by default.
  MyShell's normal path therefore uses CoreGraphics. Enabling Metal only for
  the controlled A/B sample did not reduce CPU for the 32 MiB stream and used
  roughly 17 MiB more app RSS. This workload may be dominated by parsing and
  data movement; it is not evidence that Metal is generally slower.
- `startup_to_children_ms` measures process launch until the requested PTY
  children exist. It does not prove first-frame or keyboard-ready latency.
- `ps %cpu` is a scheduler-weighted process value, not an Instruments time
  profile. The table is suitable for regression comparisons under the same
  conditions, not a general benchmark against another terminal.

### First-Stage Verification Boundaries

The automated suite verifies that terminal count is bounded, a zero-terminal
measurement state is possible, closing a PTY kills its child, writes after
close fail, output buffering is bounded, and the normal test suite remains
green. The performance launcher records only numeric process metrics; it does
not persist terminal output.

Still unproven and intentionally left for dedicated validation:

- keyboard-to-rendered-echo p95;
- first frame and first-input readiness;
- live window resize/reflow;
- real SSH throughput and disconnect behavior;
- post-output retained-memory attribution;
- 30-minute, 8-hour, and 24-hour memory/lifecycle behavior;
- Instruments App Launch, Time Profiler, Allocations, and Metal traces.

### Next Profiling Order

1. Profile the 32 MiB CoreGraphics scenario with Time Profiler and Allocations.
2. Attribute retained memory after output and compare a cleared scrollback.
3. Profile the 100 ms tab-switch scenario for `TerminalView` construction,
   replay-buffer feed, and `Data` to `[UInt8]` copies.
4. Measure first-frame and input echo with signposts rather than shell timing.
5. Repeat CoreGraphics/Metal A/B tests with scrolling, Unicode, resize, and
   multiple visible panes before considering a default renderer change.

## Second-Stage Time Profiles

2026-07-31 follow-up on the same machine and toolchain. Instruments attached
by PID to the exact Release executable because launching by bundle identifier
selected another registered development build. Window restoration was disabled,
the workload started after launch, and the retained end window excluded initial
startup work.

For a 64 MiB CoreGraphics output stream, the main inclusive sampled costs were:

| Stack | Sampled CPU time |
| --- | ---: |
| `TerminalSurface` output-consumer closure | 629 ms |
| SwiftTerm `Terminal.parse` | 577 ms |
| SwiftTerm `TerminalView.draw` | 463 ms |
| SwiftTerm escape dispatch | 349 ms |
| SwiftTerm line feed | 308 ms |
| SwiftTerm scroll | 195 ms |
| SwiftTerm attributed-row construction | 169 ms |

The stacks show that terminal parsing, scroll-row recycling, and CoreGraphics
text drawing dominate this synthetic stream. PTY read-side buffer initialization
and `Data` conversion appeared in samples but were not the leading cost. This
supports keeping renderer selection unchanged: the first-stage Metal A/B result
did not address the dominant parser and scroll work.

In the tab lifecycle experiment, a 12-terminal switch trace (100 ms interval)
included 72 ms in `TerminalView` creation, 66 ms in initialization, 42 ms in
setup, 18 ms in destruction, and 447 ms in drawing. Replay parsing was only
10 ms in this empty-shell switching workload. An experimental implementation
retained one `TerminalView` per open session and switched visibility, hit
testing, accessibility exposure, and first-responder focus. Appearance updates
were skipped unless the theme or font size changed.

Three post-change eight-second samples reported 17.887%, 16.100%, and 16.750%
average process-tree CPU (mean 16.912%), compared with the first-stage 19.600%
sample. Final app CPU was 13.8%, 19.5%, and 12.6%. A separate 12-terminal idle
sample reported 0.125% average tree CPU, 102,448 KiB app RSS, and 194,720 KiB
peak process-tree RSS. Under these short samples, retaining the views did not
produce a demonstrated idle-memory regression, and the steady-state trace no
longer contained `TerminalView` creation or destruction. The experiment was
not retained as the product default after the concurrent-output test below.

### Second-Stage Boundaries

- The CPU comparison is a local regression indicator, not a statistically
  rigorous benchmark; repeat it on release hardware before setting a target.
- Retained terminal views consume output for inactive sessions. A dedicated
  multi-session output test is still required to bound background CPU.
- The Time Profiler result attributes active CPU, not retained allocations.
  Allocations/VM Tracker and a post-output quiescence window are still needed
  to explain the high-water RSS. The attempted follow-up allocation trace was
  discarded because its metadata inherited unrelated sensitive environment
  variables; no allocation conclusion was drawn from it.
- Visibility changes still cause SwiftTerm/CoreGraphics redraw work. A custom
  Metal renderer is not justified until real scrolling, Unicode, resize, and
  multi-session workloads show a user-visible or energy benefit.

## Third-Stage Concurrent Output and Lifecycle

2026-07-31 controlled Release samples on the same machine. Each terminal
received 8 MiB of ASCII output, so the 1/4/12-session runs processed 8, 32, and
96 MiB in total.

| View policy | Terminals | Tree average CPU | Final app CPU | App RSS | Tree peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Retain every `TerminalView` | 1 | 16.192% | 0.0% | 215,344 KiB | 221,152 KiB |
| Retain every `TerminalView` | 4 | 65.342% | 0.0% | 413,856 KiB | 441,648 KiB |
| Retain every `TerminalView` | 12 | 172.467% | 118.8% | 1,112,928 KiB | 1,163,264 KiB |
| Selected `TerminalView` only | 12 | 135.525% | 0.0% | 248,672 KiB | 408,704 KiB |

The retained-view policy made tab switching about 13.7% cheaper in the earlier
sample, but under 12-session output it used more than four times the app RSS and
had not returned to idle after 12 seconds. MyShell therefore keeps only the
selected `TerminalView` mounted. The retained policy remains available only as
a performance-mode A/B switch. A final eight-second default-policy tab-switch
sample reported 17.512% average tree CPU, 20.4% final app CPU, 143,136 KiB app
RSS, and 200,384 KiB peak tree RSS.

In a separate 12-session run, every shell produced 8 MiB and then exited.
After an eight-second stabilization window the app reported 0.0% CPU,
326,240 KiB RSS, and zero child processes. This confirms PTY children are
reaped after normal shell exit. The RSS remains above the idle baseline while
the twelve exited session models and their bounded replay buffers remain open;
tab removal and allocator attribution still require a clean allocation trace.

The performance script now reports final direct-child count and provides
`concurrent-output` and `exit-after-output` scenarios. Output remains bounded
to 64 MiB per terminal and terminal count remains bounded to twelve.

## Fourth-Stage Retained-Memory Attribution

2026-07-31 `footprint` and `vmmap` samples used the same Release executable and
a minimal launch environment. Unlike the discarded Instruments trace, these
reports did not persist the full parent environment.

| 12-terminal state | Physical footprint | Peak | Main dirty categories |
| --- | ---: | ---: | --- |
| Idle | 130.6 MiB | 189.0 MiB | IOSurface 49.1 MiB, large heap 31.2 MiB, small heap 28.0 MiB |
| 12×8 MiB output, shells exited, original buffer | 374.5 MiB | 427.1 MiB | large heap 133.4 MiB, small heap 120.9 MiB, owned unmapped 56.0 MiB |
| 12×8 MiB output, shells exited, ring buffer | 201.4 MiB | 327.4 MiB | small heap 82.3 MiB, IOSurface 48.9 MiB, large heap 48.0 MiB |

The original `BoundedByteBuffer` repeatedly removed bytes from the front of a
`Data` value and appended each new PTY chunk. Under sustained output this
created large transient allocations and allocator high-water retention. It now
uses lazily allocated fixed-capacity ring storage and direct memory copies.
Ordered `Data` is materialized only when a terminal surface attaches.

The same script-level 12×8 MiB workload changed from 135.525% to 129.742%
average process-tree CPU, from 248,672 to 235,616 KiB final app RSS, and from
408,704 to 300,800 KiB peak process-tree RSS. Final app CPU remained 0.0%.
This is approximately a 26% reduction in peak tree RSS without a measured CPU
regression in the final direct-copy implementation.

About 48 MiB of large heap is expected from twelve 4 MiB replay buffers after
all sessions have produced enough output. The remaining increase is primarily
the selected SwiftTerm surface's parsed scrollback and small-object heap.
Reducing replay capacity or the 10,000-row scrollback would change user-visible
history retention, so neither limit was reduced in this stage.

## Fifth-Stage Interaction and Unicode Workloads

2026-07-31 Release measurements added a performance-mode-only latency probe.
It records only sample number, stage, and elapsed microseconds through unified
logging category `TerminalLatency`. It does not log input bytes, commands, or
terminal output. Normal launches do not enable the probe.

Twenty local-shell samples sent one bounded synthetic command every 500 ms.
The first sample was treated as cold; the remaining nineteen produced:

| Stage from send | Warm p50 | Warm p95 | Warm range |
| --- | ---: | ---: | ---: |
| PTY output received | 1.314 ms | 1.682 ms | 0.539–1.682 ms |
| SwiftTerm feed completed | 1.527 ms | 1.838 ms | 0.629–1.838 ms |
| Core Animation display transaction committed | 1.766 ms | 2.021 ms | 0.722–2.021 ms |

The cold display-commit sample was 5.360 ms. Display transaction completion is
closer to presentation readiness than feed completion, but it is not a
photodiode or screen-capture measurement of photons on screen. These figures
therefore establish an internal local-echo baseline, not absolute perceived
keyboard latency.

A byte-count comparison proved misleading because the shorter ASCII line
caused many more line feeds and scroll operations per MiB. The repeatable
`same-lines` scenario instead emitted 100,000 lines in each profile:

| Profile | Tree average CPU | Final app CPU | App RSS | Tree peak RSS |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 22.567% | 7.2% | 196,176 KiB | 207,408 KiB |
| Unicode + ANSI | 28.167% | 0.0% | 196,784 KiB | 212,416 KiB |

At the same line count, Unicode, wide characters, a combining mark, and ANSI
color increased average CPU by about 25%, while final memory was similar.
This supports treating glyph shaping and attribute handling as a secondary
cost after line-feed/scroll processing. The scenario is synthetic and still
does not cover Emoji sequences, bidirectional text, selection, search, or live
window reflow.

## Sixth-Stage Window Resize and Reflow

2026-07-31 Release measurements used a performance-mode-only `NSWindow` driver.
After loading 10,000 history lines, it alternated the main window between its
minimum content size and 78% of the current display's visible area. The driver
does not assume a fixed monitor size and does not alter normal window
restoration or placement.

The scenario performed 100 size changes at 100 ms intervals:

| Renderer | Tree average CPU | Final app CPU | App RSS | Tree peak RSS |
| --- | ---: | ---: | ---: | ---: |
| CoreGraphics | 17.487% | 1.3% | 164,800 KiB | 189,264 KiB |
| SwiftTerm Metal | 21.513% | 1.1% | 177,616 KiB | 222,192 KiB |

In this reflow workload, SwiftTerm Metal used about 23% more average CPU,
12.5 MiB more final app RSS, and 32.2 MiB more peak process-tree RSS.
Both paths returned close to idle after resizing stopped. This is further
evidence against enabling SwiftTerm Metal by default; it is not a comparison
with Otty's separate native Metal renderer.

Unified log category `WindowResize` records only requested cycles, interval,
completion, and aggregate terminal resize-event count. A five-cycle verification
completed with eight terminal resize callbacks, including initial/intermediate
layout changes, confirming the window mutations propagated through SwiftTerm to
the PTY resize path. No dimensions, terminal content, or commands are logged.

## Seventh-Stage Full-Screen TUI

2026-07-31 Release measurements added a deterministic alternate-screen
workload representing the control paths shared by `top`, `htop`, and editors:
enter/leave alternate screen, home cursor, 40-row full-screen updates, ANSI
colors, and 1,000 frames. Frame count is bounded to 10,000 and normal launches
do not enable the generator.

The first 15-second samples were effectively tied at 14.020% CoreGraphics and
13.660% Metal average tree CPU. Two matched 12-second repeats produced:

| Renderer | Mean tree CPU | Mean app RSS | Mean tree peak RSS |
| --- | ---: | ---: | ---: |
| CoreGraphics | 19.829% | 112,544 KiB | 127,768 KiB |
| SwiftTerm Metal | 19.138% | 115,568 KiB | 134,480 KiB |

The roughly 3.5% CPU difference is too small and variable to establish a Metal
advantage. Metal used about 3.0 MiB more final app RSS and 6.6 MiB more peak
tree RSS in the matched repeats. Both renderers returned to idle and retained
one interactive shell.

A synthetic OSC title marker sent after leaving alternate screen produced one
bounded `TerminalTUI` completion event, while the Zsh child remained alive.
This verifies the terminal resumed normal sequence parsing after the TUI.
The marker is consumed only in performance mode and is not exposed as the
session title.

A five-second system sample during a 10,000-frame run placed the leading app
work in the `TerminalSurface` output consumer, `EscapeSequenceParser` CSI
dispatch, and `TerminalView.drawTerminalContents`. This matches the earlier
parser/drawing attribution and does not indicate that PTY generation is the app
bottleneck.
