# Installing Menu Bar Monitor

Menu Bar Monitor is a small macOS app with no installer and no dependencies to fetch.
Building it from source takes about ten seconds and is the recommended route, because it
sidesteps Gatekeeper entirely.

- [Requirements](#requirements)
- [Build from source](#build-from-source)
- [Install it](#install-it)
- [Start it at login](#start-it-at-login)
- [Using a downloaded release](#using-a-downloaded-release)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| macOS | 14 (Sonoma) or later |
| Toolchain | Swift 6 — Xcode, or the Command Line Tools |
| Disk | ~1 MB for the installed app |
| Network | None, to build or to run |
| Permissions | None needed. Location Services only if you want to see the Wi-Fi network's name |

If you do not have a toolchain yet:

```bash
xcode-select --install
```

That gives you `swift`, `codesign` and `iconutil`, which is everything `build.sh` uses.
Check it worked:

```bash
swift --version   # expect 6.x
```

## Build from source

```bash
git clone https://github.com/rwijnen/menu-bar-monitor.git
cd menu-bar-monitor
./build.sh
```

That produces `build/MenuBarMonitor.app`: ad-hoc signed, with a generated icon. Try it
before installing:

```bash
open build/MenuBarMonitor.app
```

It appears in the menu bar, not the Dock. To quit it, click any of its items and choose
**Quit** at the bottom of the dropdown.

## Install it

```bash
./build.sh --install
```

Copies the app to `/Applications` — falling back to `~/Applications` if that is not
writable — quits any copy that is already running, and starts the new one.

CPU, memory and network are three separate items. To move one along the menu bar, hold ⌘
and drag it; macOS remembers where you put each.

## Start it at login

Open the dropdown, choose **Settings** and turn on **Launch at login**. It is registered
with the system's login items, so it also appears in **System Settings → General → Login
Items**, where you can switch it off again. If macOS asks you to approve it there, the
settings window says so.

## Using a downloaded release

Release builds are **ad-hoc signed, not notarised** — this project has no paid Apple
Developer certificate. macOS will therefore refuse to open a downloaded build until you
clear the download quarantine:

```bash
unzip MenuBarMonitor.app.zip -d /Applications
xattr -dr com.apple.quarantine /Applications/MenuBarMonitor.app
open /Applications/MenuBarMonitor.app
```

Or, without the terminal: right-click the app in Finder, choose **Open**, and confirm the
warning once. macOS remembers the decision.

Verify what you downloaded against the published checksum:

```bash
shasum -a 256 MenuBarMonitor.app.zip   # compare with MenuBarMonitor.app.zip.sha256
```

If an unverifiable publisher is not acceptable to you, build from source instead. The
result is identical and carries your own ad-hoc signature.

## Updating

```bash
git pull
./build.sh --install
```

Settings are kept in `UserDefaults` under `com.robinwijnen.menubarmonitor` and survive a
reinstall. It stores two things only: your settings, and today's download and upload
totals, so they survive a restart.

## Uninstalling

Turn off **Launch at login** in Settings first, if you turned it on. Then quit the app and:

```bash
rm -rf /Applications/MenuBarMonitor.app
defaults delete com.robinwijnen.menubarmonitor 2>/dev/null || true
```

It writes nothing else anywhere: no caches, no support folder, no helper.

## Troubleshooting

**An item does not appear in the menu bar**
macOS hides menu bar items that do not fit, without saying so — on a MacBook with a notch,
items to the left of the notch are the first to go. Quit an app with its own menu bar item,
pick **Mini bars** in Settings, which is the narrowest style, or switch off a metric you can
do without. Check it is running with
`pgrep -x MenuBarMonitor`.

**Memory is amber or red**
That is macOS's own memory pressure level, not a threshold the app picks: amber means the
system is compressing memory and using swap to keep up. Activity Monitor's Memory tab shows
the same thing as its pressure graph. Turn off **Colour warnings** if you would rather not
see it.

**An app shows more than 100%**
App figures are per core, as in Activity Monitor and Stats: 100% is one core kept busy, so
an app using four cores shows about 400% while the CPU total above it says 25% on a
sixteen-core Mac. An app's helper processes are added in, so it can be higher than any of
its processes in Activity Monitor.

**Temperature or clock speed shows "—"**
Apple publishes no interface for either on Apple silicon, so they come from undocumented
ones that need no root. They are not there on Intel Macs or in virtual machines, and a
macOS update could take them away. Everything else keeps working.

**The CPU dropdown says "Measuring…"**
The process list comes from running `ps` when the dropdown opens, and takes a moment to
arrive. The clock speed is the difference between two readings, so it appears about half a
second later.

**The Wi-Fi network shows "Location Services off"**
macOS gives network names only to apps allowed to use Location Services, and it was
refused or is switched off. Turn on Menu Bar Monitor in **System Settings → Privacy &
Security → Location Services**. An app you build from source is signed afresh each time,
so macOS may ask again after a rebuild.

**The connection says "None" while the Wi-Fi is on**
The connection status is macOS's own view of whether it has a usable path to the network.
The app does not test the internet itself — that would mean sending traffic — so a
network whose router has lost its connection can still show as connected, and one that
macOS has not finished joining shows as none.

**`./build.sh: Permission denied`**
`chmod +x build.sh`.

**The icon did not build**
`build.sh` prints `skipped (icon generation unavailable — the app still builds)` and
carries on. The app works; only the icon is missing. It needs `iconutil`, which ships with
the Command Line Tools.

**Nothing above matches**
[Open an issue](https://github.com/rwijnen/menu-bar-monitor/issues/new/choose) with your
macOS version, your Mac (Apple silicon or Intel), how you installed, and the output of
`MenuBarMonitor --sample` if a number looks wrong.
