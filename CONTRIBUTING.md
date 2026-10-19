# Contributing to Menu Bar Monitor

Thanks for looking. Menu Bar Monitor is a spare-time project with one maintainer, so the
most useful contributions are small, verified and easy to review.

- [What it is, and is not](#what-it-is-and-is-not)
- [Getting set up](#getting-set-up)
- [The layout of the code](#the-layout-of-the-code)
- [Running the tests](#running-the-tests)
- [Verifying the interface](#verifying-the-interface)
- [Measuring the cost](#measuring-the-cost)
- [Style](#style)
- [Commits and pull requests](#commits-and-pull-requests)
- [Common tasks](#common-tasks)
- [Releasing](#releasing)

## What it is, and is not

Three constraints shape every decision, and a change that breaks one of them will not be
merged:

1. **It never goes online.** Not at build time and not at run time. Every figure it shows
   is a counter the kernel already keeps on your Mac; the network graph reads byte
   counters and the connection status is macOS's own, so nothing is sent. No update
   check, no telemetry, no latency test, no remote images or fonts. A feature that opens
   a connection will not be merged.
2. **It needs no privileges of its own.** No root helper, no kernel extension, no
   entitlements. The process lists come from `/bin/ps` and `/usr/bin/top` — installed
   setuid root to see every user's processes — and `/usr/bin/nettop`, run with fixed
   arguments while the matching dropdown is open. The one permission prompt is Location
   Services, shown only when the user clicks to see the Wi-Fi network's name; nothing
   may ask for a permission by itself.
3. **It costs less than what it measures.** About 18 MB of memory and under 1% CPU at the
   default two-second interval. A change that raises either needs a measurement in the
   pull request and a good reason (see [Measuring the cost](#measuring-the-cost)).

Beyond that: it favours being *right about the numbers* over showing more of them, and it
prefers native Swift over dependencies. There are none, and adding the first needs a good
argument.

## Getting set up

```bash
git clone https://github.com/rwijnen/menu-bar-monitor.git
cd menu-bar-monitor
swift build          # compile
swift test           # the whole suite, under a second
./build.sh           # assemble build/MenuBarMonitor.app
open build/MenuBarMonitor.app
```

You need macOS 14+ and a Swift 6 toolchain. `build.sh` uses only `swift`, `codesign` and
`iconutil`, all of which ship with the Command Line Tools.

## The layout of the code

```
Sources/MenuBarMonitor/
  Model/       pure logic, no UI, all of it tested
    CPUSampler        per-core tick counters → usage, from host_processor_info
    MemorySampler     host_statistics64, swap and the pressure level
    NetworkSampler    64-bit byte counters on the primary interface, its name, status and
                      addresses
    ConnectionMonitor macOS's own view of whether it has a connection, and its history
    WiFiName          the Wi-Fi network's name, behind Location Services permission
    CoreLayout        which cores are which kind (Performance, Super…), from sysctl;
                      SystemInfo: load average, uptime, the chip's name
    TemperatureSampler the CPU die sensors, through undocumented IOHID calls
    FrequencySampler  clock speed per cluster, from IOReport and the power manager
    ProcessSampler    `ps` (CPU) or `top` (memory) for every process, grouped under the
                      app responsible for it
    Readings          the values the samplers return
    Metric            CPU, memory and network: one menu bar item each
                      DropdownState: which item's dropdown is open (at most one)
    Format            how every number is written
  State/
    MetricsStore      takes a reading each tick and keeps a minute of history
    AppSettings       the user's choices, kept in UserDefaults
  Views/
    MenuBarLabel      MetricLabel, what sits in one item in each of the three
                      styles; MenuBarLabel, all of them together, for previews
    PanelView         one metric's dropdown
    SettingsView      the settings window, with a live preview of each style
    Sparkline         the graph shape, the mini bar and the memory bar
    Bars              per-core bars, the stacked memory bar and the connection strip
    Theme             the palette and the warning colours
  App/
    main              starts the app, or a developer command
    AppDelegate       a status item per metric, which dropdown is open, settings
    DropdownPanel     the borderless panel under the status item
    DevTools          --sample and --snapshot
Tools/make-icon.swift draws the icon with Core Graphics
```

[Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) describes the components and how they fit
together, and why several of them are not the obvious approach — read that before a
structural change.

The rule of thumb: **logic belongs in `Model/`, where it can be tested**. Views should
assemble and display, not compute.

## Running the tests

```bash
swift test                              # everything
swift test --filter FormatTests         # one suite
swift test --filter rateWidth           # one test
```

Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`,
`#expect`, `#require`), not XCTest — deliberately, since XCTest is unavailable without
Xcode.

The sampler suite reads the real counters of whatever machine runs it, so it checks shape
and consistency (memory used is app + wired + compressed, CPU stays within 0–100, the first
reading has no rate) rather than exact values. Everything else is fed known readings
through `MetricsStore.record(…)`, which is the seam to use for new state logic.

Settings tests each use their own `UserDefaults` suite, so they cannot read or change the
installed app's settings. Keep that up if you add one.

**New behaviour needs a test.** If it lives in `Model/`, that is straightforward. If it
lives in a view, look for the seam: most view logic worth testing can move into `Model/`,
as the number formatting and the sparkline geometry did.

## Verifying the interface

Please do not send a UI change with "looks right to me" as the only evidence. Both of these
work headlessly and need no screen-recording permission:

**`--snapshot <dir>`** renders the menu bar items in every style, each metric's dropdown
and the settings window, in light and dark, from fixed demo data:

```bash
swift build -c release && .build/release/MenuBarMonitor --snapshot Docs
```

That is how the screenshots in `Docs/` are made, so regenerate them when a view changes.
Two things it cannot show: the material behind the dropdowns, which blurs whatever is on
screen behind them — offscreen there is nothing, so the dropdowns are rendered on a plain
background — and the items' place among the other menu bar icons. For those, run the app
and look, in dark mode as well as light, and over a bright window as well as a dark one:
that combination is how the first dropdown, on Liquid Glass, turned out unreadable.

**`--sample`** prints four rounds of live readings, a second apart. Compare them with the
system's own tools:

```bash
.build/release/MenuBarMonitor --sample
top -l 2 -s 1 -n 5 -o cpu       # CPU usage, PhysMem wired and compressor
sysctl vm.swapusage
route -n get default | grep interface
```

## Measuring the cost

Constraint 3 is checked, not assumed. With the app running from `./build.sh --install`,
after it has been up for half a minute:

```bash
footprint -p "$(pgrep -x MenuBarMonitor)" | grep -E "Footprint|graphics"
top -l 2 -s 10 -pid "$(pgrep -x MenuBarMonitor)" -stats pid,cpu | tail -1
```

Look at the `graphics` lines as well as the total: GPU memory the process owns counts
against it. The CPU and memory dropdowns' extras run only while they are open, so
measure with every dropdown closed and again with each of those two open. Switching the sparklines from `Canvas` to shapes took the footprint from 94 MB
to 18 MB, and almost all of the difference was there.

## Style

Match the surrounding code; there is no formatter to run.

- Four-space indentation, ~96 column soft limit.
- Full words for names: `downloadPerSecond`, not `dlps`. Types are nouns, functions are
  verbs.
- `// MARK: -` sections in anything over about 100 lines.
- **Comments explain why, not what.** The valuable ones say why the obvious approach was
  not taken — why the network counters come from the interface MIB and not `getifaddrs`, why the
  status item hosts a SwiftUI view rather than using `MenuBarExtra`. Do not narrate the
  code.
- British spelling in prose, including comments and interface text.
- No new dependencies without discussing it first.

## Commits and pull requests

**Nothing is committed straight to `main`.** Every change — features, fixes, even
documentation — goes on a branch and reaches `main` through a pull request, so there is
always a diff to read and a green CI run before anything lands.

```bash
git switch main && git pull
git switch -c feature/what-it-does      # or fix/… or docs/…
# work, commit
git push -u origin feature/what-it-does
gh pr create --base main --fill
```

- One concern per pull request. A refactor and a feature in the same diff is hard to
  review.
- Commit subjects in the imperative, under ~72 characters:
  `Keep the network column the same width at every rate`.
- Explain the *why* in the body when it is not obvious.
- Fill in the pull request template's **How it was verified** section honestly, including
  what you did not check. "I could not check dark mode because …" is a perfectly good
  answer; a false claim is not.
- CI must be green: build, tests, a bundle check and a smoke run of `--sample` on macOS.

## Common tasks

**Add a metric.** A case in `Metric`, with a title, a symbol and an autosave name — which,
like a style's raw value, is stored on disk and must never be renamed. A sampler in
`Model/` that returns a reading struct (see `Readings`), called from
`MetricsStore.sample()` and stored by `record(…)` with its own history. Then its section in
`PanelView` and its label in `MetricLabel` for each style — the compiler points at every
`switch` — a stored toggle in `AppSettings`, and demo values in `DevTools` so the
screenshots show it. The status item, its dropdown and the Settings toggle follow from the
`Metric` case by themselves. Test the
sampler against the live machine and the store with known readings.

**Add a menu bar style.** A case in `MenuBarStyle` with a title and subtitle — its raw
value is stored on disk, so never rename one later. The compiler then points at every
`switch` in `MetricLabel` that needs it. Settings and `--snapshot` pick it up by
themselves. Check the item's width against the others: the menu bar hides items that do
not fit, and on a notched MacBook that happens quickly.

**Change a colour.** `Palette` in `Views/Theme.swift`. There is one colour per metric —
purple for CPU, teal for memory, coral and grey for network — and a breakdown uses tones
of its metric's colour rather than new ones; red and amber are kept for warnings. Every
colour has to work on a light and a dark menu bar and dropdown, so check both snapshots,
and in the running app check dark mode over a bright window.

**Touch the icon.** `Tools/make-icon.swift`, pure Core Graphics. Palette constants are at
the top. Always check the 16 and 32 pixel variants: below 64 pixels the drawing takes a
different, much simpler path, because the sparklines turn to mush there.

## Releasing

**A pull request that changes the app is a release.** If it touches `Sources/` or
`Resources/`, it carries its own version bump, and CI's *Version bump* check fails it
otherwise. Docs, tests and CI changes need none, so a README fix does not become a version.

1. Update `CHANGELOG.md`: this PR's entries go under a new `## [X.Y.Z]` heading below
   *Unreleased* (fix → patch, feature → minor), with the compare links updated.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
3. `.github/scripts/check-version-bump.sh main`, then `swift test && ./build.sh`.
4. Merge it. **Landing a version bump on `main` publishes the release**: the workflow
   reads the version out of the bundle, sees there is no tag for it yet, and builds,
   tags and publishes. Anything else on `main` publishes nothing.

Tagging by hand still works — `git tag -a v1.1.0 -m "Menu Bar Monitor 1.1.0" && git push
origin v1.1.0` — and is the way to publish a version whose bump has already landed.

The workflow refuses to publish unless `CHANGELOG.md` has a heading for the version (and,
for a hand-pushed tag, unless the tag matches `CFBundleShortVersionString`), so steps 1
and 2 are checked rather than trusted. Actions are pinned by commit rather than by a major
tag: a floating tag moving is not visible in any diff, and the run it breaks is the
release, which nobody watches. It builds, runs the tests, and attaches a zip plus its
SHA-256. The artifact is ad-hoc signed and not notarised, and the release notes say so.
