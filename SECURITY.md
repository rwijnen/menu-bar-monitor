# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private
reporting instead:

> [Report a vulnerability](https://github.com/rwijnen/menu-bar-monitor/security/advisories/new)

That opens a private advisory visible only to you and the maintainer. If you would rather
not use GitHub, the maintainer's contact address is on their
[GitHub profile](https://github.com/rwijnen).

Expect an acknowledgement within a week. This is a spare-time project with one
maintainer, so please be patient with fixes — and say if you intend to disclose publicly
on a schedule, so it can be met.

## What Menu Bar Monitor is exposed to

Very little, by design. It opens no files, accepts no documents and talks to no server.
What it takes in is what the kernel reports about your own Mac — counters, process names,
interface names — and the threat model is mostly about what it must *not* do with that:

1. **It never goes online.** There is no networking code in the app. The network graph
   reads byte counters the kernel keeps per interface (`sysctl NET_RT_IFLIST2`); it does
   not send, probe or resolve anything. No update check, no telemetry.
2. **It needs no privileges of its own.** No root helper, no kernel extension, no
   entitlements, and no permission prompts. To list other users' processes in the CPU
   dropdown it runs `/bin/ps -Aceo pid=,pcpu=,comm=`, which macOS installs setuid root for
   exactly that. It is the only program the app starts, its arguments are fixed, and it
   runs only while the CPU dropdown is open.
3. **It writes only its own preferences.** Its settings and today's traffic totals, in
   `UserDefaults` under `com.robinwijnen.menubarmonitor`. Nothing else, anywhere.

Process names and app names come from other programs and are shown in the dropdown, so
they count as input. They are parsed from `ps` by column, drawn as plain text by SwiftUI,
and never interpreted.

Findings that would be especially valuable:

- Anything that makes the app reach the network.
- A way for it to read information about processes it should not be able to see.
- A crash or a hang from an unusual system state: an interface appearing or vanishing
  mid-reading, thousands of processes, a process name with unexpected bytes in it.
- Anything that makes its CPU or memory use grow without bound while it runs.

## Known, accepted limitations

- **Release builds are ad-hoc signed, not notarised.** There is no paid Apple Developer
  certificate behind this project, so downloaded builds carry no verifiable publisher
  identity. If that matters to you, build from source — see [INSTALL.md](INSTALL.md).
- **The app is not sandboxed.** The App Sandbox restricts reading other processes'
  details, which the busiest-apps list depends on.
- **It uses undocumented system interfaces**, each looked up at run time with `dlsym`,
  so a future macOS that removes one makes that one figure disappear rather than the app
  fail:
  - `responsibility_get_pid_responsible_for_pid`, to count a helper process under the app
    that owns it. Without it, grouping falls back to the app bundle in each process's
    path.
  - IOHID's event-system client, to read the CPU die temperature sensors.
  - IOReport (`libIOReport`), with the power manager's frequency tables from the I/O
    Registry, to work out clock speeds. `powermetrics` reports the same but needs root.
  None of them needs privileges; they are read-only.
- **The code was written by an AI and has not been independently audited.** Menu Bar
  Monitor was vibecoded in Claude Code; see
  [How this was built](README.md#how-this-was-built). The rules above are covered by
  tests and by measurement, but tests only cover what someone thought to check, and no
  third party has reviewed this.

## Supported versions

The latest release and `main` are supported. There are no long-term support branches.
