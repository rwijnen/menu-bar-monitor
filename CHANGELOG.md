# Changelog

All notable changes to Menu Bar Monitor are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rwijnen/menu-bar-monitor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/rwijnen/menu-bar-monitor/releases/tag/v1.0.0
