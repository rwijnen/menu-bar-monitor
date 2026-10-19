## What this changes

<!-- One or two sentences. If it fixes an issue, add "Fixes #123". -->

## How it was verified

<!--
Please be specific, and honest about what you did not check. For example:
- `swift test` — all suites pass
- `--sample` compared with `top -l 2` and `sysctl vm.swapusage`
- `--snapshot` rendered and looked at, light and dark
- Ran it from `./build.sh --install` and opened the dropdown
-->

- [ ] Changes `Sources/` or `Resources/`? Then this PR bumps the version in
      `Resources/Info.plist` and adds its `## [X.Y.Z]` CHANGELOG heading, or merging
      publishes nothing (CI's *Version bump* check enforces it)
- [ ] `swift test` passes
- [ ] `./build.sh` produces a working app bundle
- [ ] Checked the behaviour in the running app, or explained below why not
- [ ] Touches sampling or drawing? Then the memory and CPU of the running app are below,
      before and after (see *Measuring the cost* in CONTRIBUTING.md)

## Notes for the reviewer

<!-- Trade-offs, things you were unsure about, follow-up work you left out. -->
