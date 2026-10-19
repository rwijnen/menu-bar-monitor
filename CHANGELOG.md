# Changelog

All notable changes to Menu Bar Monitor are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.0] — 2026-10-20

### Changed

- **The dropdowns go back to the look of the first mock-up**, keeping everything they now
  show: quiet sections divided by hairlines, a heading with the figure that matters
  most, graphs without frames, and rows of label and value. Each metric keeps one
  colour — purple for CPU, teal for memory, coral and grey for network — with tones of it
  for a breakdown, such as the kinds of core or app, wired and compressed memory. The
  rings, the pressure dial, the mirrored network graph, the status badges, the uppercase
  titles and the pink, blue, orange and green accents are gone.

## [1.4.0] — 2026-10-20

### Added

- **The network dropdown shows much more**, after Stats: download and upload in large
  figures; a minute of history with upload above the line and download below, each to
  its own scale; a connectivity history of the last ninety readings; totals since the
  Mac started beside today's; the interface's status, hardware address and local IP;
  and the apps moving the most data, from `nettop`, grouped by app.
- **The Wi-Fi network's name**, after you click to allow Location Services — macOS gives
  network names only to apps with that permission. The app never reads your location.

The connection status is macOS's own view of whether it has a connection: the app still
never goes online, so unlike Stats it shows no latency or jitter.

### Fixed

- **Totals since boot, and rates across a 4 GB boundary.** The Wi-Fi download counter
  wrapped at 4 GB in the source used before, so every 4 GB downloaded showed one reading
  of no traffic. The counters now come from the interface MIB, the source `netstat -ib`
  uses, which has the full 64-bit count.

## [1.3.1] — 2026-10-19

### Fixed

- **The dropdowns can be read in dark mode.** On macOS 26 they sat on Liquid Glass, which
  over a bright window stayed light grey while the text stayed white. They now use the
  popover material, which darkens in dark mode whatever is behind it — as on earlier
  versions of macOS, where this was already the case.

## [1.3.0] — 2026-10-19

### Added

- **The memory dropdown shows much more**, laid out like Stats: a dial for macOS's memory
  pressure, a ring of memory used split into app, wired and compressed, a minute of
  history, the breakdown as a bar with free memory and swap, and the eight apps using the
  most memory, system processes included. Apps are measured by physical footprint, the
  figure in Activity Monitor's Memory column, from `top`, which runs only while the
  dropdown is open — when it opens and every ten seconds after — since one run costs
  about 0.6 s of CPU.

### Changed

- **Processes that are not part of an app are named in full**, from their executable,
  in both process lists: `com.apple.Virtualization.VirtualMachine` rather than the first
  sixteen characters of it.

## [1.2.0] — 2026-10-19

### Added

- **The CPU dropdown shows much more**, laid out like Stats: gauges for temperature, usage
  and clock speed; a minute of history above a bar for each core, coloured by kind
  (Performance and Super cores on an M5 Pro, Efficiency and Performance on earlier chips);
  system, user and idle time and each kind of core's usage; uptime; the load average over
  1, 5 and 15 minutes; and the clock speed of all cores and of each kind. Temperature and
  clock speed come from interfaces Apple does not document and show "—" where those do
  not answer, such as on Intel Macs.

### Changed

- **The busiest apps include system processes** such as `WindowServer` and `kernel_task`,
  and the list is eight long. It comes from `ps`, which runs only while the CPU dropdown is
  open. Helper processes are still counted under their app.
- **App CPU is per core, as in Activity Monitor**: 100% is one core kept busy, so a busy
  app can pass 100%. It used to be a share of the whole machine.

## [1.1.0] — 2026-10-19

### Changed

- **Each metric is its own menu bar item, with its own dropdown.** Clicking the CPU graph
  shows CPU, the memory graph memory, the network rates network — instead of one dropdown
  with all three. Clicking another item moves the dropdown there; a click anywhere else
  closes it. Each item can be ⌘-dragged to its own place, and macOS remembers it. An item
  that is switched off in Settings leaves the menu bar entirely, and its dropdown closes
  if it was open.

## [1.0.0] — 2026-10-19

### Added

- **CPU, memory and network in the menu bar**, in three styles: sparklines of the last 20
  readings (the default), mini level bars, or icons and numbers. Upload and download are
  always shown as numbers, sized to their widest value so the item never shifts sideways.
- **A dropdown** with a minute of history for each metric. CPU is split into user and
  system time and lists the three busiest apps, with helper processes counted under the
  app responsible for them. Memory shows what Activity Monitor calls *Memory Used* (app,
  wired and compressed), the pressure level and swap. Network shows the interface macOS
  routes through, its address, and today's totals, which survive a restart and reset at
  midnight. It uses the system's glass material on macOS 26 and later.
- **Settings**: the menu bar style, with a live preview of each; which metrics to show;
  the update interval (1, 2 or 5 seconds); colour warnings; and launch at login.
- **Colour warnings**: CPU turns red above 85%, memory amber or red when macOS reports
  memory pressure.
- `--sample` prints live readings to compare with `top` and `vm_stat`, and
  `--snapshot <dir>` renders every view to PNG from demo data — neither needs
  screen-recording permission.

[Unreleased]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/rwijnen/menu-bar-monitor/releases/tag/v1.0.0
