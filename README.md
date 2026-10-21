# SimWalk

Your agent changed one view. SimWalk checks every screen, in every state, before review does.

![A recording of a SimWalk run: the Simulator on the left walks a demo app's Account screen in light, dark, large-text and Arabic right-to-left states, sped up six times; the terminal on the right then prints the structural diff against a baseline run, five overlap lines such as "Storage" over "{n} GB of {n} GB", beside the flagged crop before and after.](Docs/Images/hero.gif)

SimWalk opens your iOS app in the Simulator, or on a connected iPhone or iPad. It goes to each screen you
list and captures it in each state you ask for: dark mode, large text, another language, right to left.
Then it tells you, in a few lines of text, what changed and what is wrong. The nine-capture walk below is
answered in about 1.5 kB, roughly 370 tokens: less context than a single screenshot (about 4.1k).

## The problem

You changed a view. To know nothing else broke, you would open every screen in dark mode, at the largest
text size, in Arabic, and look. With 30 screens and 4 states that is 120 checks. So it does not happen,
and the breakage turns up in a review or a bug report.

The usual tools each fall short.

- **Pixel snapshot tests** fail when a clock ticks or a number changes, and they pass when a whole
  section has vanished. `simwalk bundle diff` compares two runs by structure instead: which sections are
  there, in what order, whether text overlaps text, whether a chart has nothing plotted. New data is not a
  failure. A missing section is.
- **UI tests** that miss a tap still produce a screenshot, of the wrong screen. SimWalk reports a screen it
  could not reach as `UNREACHABLE` and names the route it tried. If you ask for dark mode and the device
  ignored it, SimWalk refuses to file the capture as dark. You can also say which accessibility identifier
  a screen must carry (`expect`), and a screen without it is flagged.
- **A screen can look perfect and show yesterday's total.** `simwalk bundle oracle` reads the figures you
  name off the screen and checks them against a small program of yours that computes the right values.
- **Accessibility problems turn up late.** `simwalk bundle audit` checks every capture for controls with no
  label, SF Symbol names read out as labels, duplicate labels, tap targets under 44 pt, reading order that
  does not match the layout, text that overflows at accessibility sizes, text drawn truncated with an
  ellipsis (read from the screenshot), and tappable rows that are not exposed as controls.
- **A coding agent that looks at screenshots pays thousands of tokens per screen.** SimWalk gives it the
  screen as text, a fraction of a screenshot's size, and most answers state how many tokens that saved.
- **Parallel runs fight over one simulator.** A lease gives each walk, agent or CI job a device of its own.

Your app needs no changes and no test target. SimWalk reads the accessibility tree through XCUITest, from
a runner of its own.

## Try it in two minutes

This uses Apple's Settings app, so there is nothing of yours to build. Install SimWalk first (see
[Install](#install)).

A walkbook is a JSON file that lists the screens to visit and how to reach each one. The repo has one for
Settings, `Fixtures/Settings/settings.walkbook.json`. Here are two of its five screens.

```json
{
  "name": "apple-settings",
  "appBundleID": "com.apple.Preferences",
  "screens": [
    {
      "id": "general",
      "route": [{ "tap": { "label": "General" } }],
      "states": [{ "theme": "light" }, { "theme": "dark" }]
    },
    {
      "id": "accessibility",
      "expect": "AccessibilitySettingsControllerView",
      "route": [{ "tap": { "label": "Accessibility" } }],
      "states": [{ "theme": "light" }]
    }
  ]
}
```

Each screen has three keys that matter here.

- `route` is the taps to reach the screen from a fresh launch. A label is the accessibility label you see
  on screen. Other steps are `tab`, `scrollTo`, `type`, `back`, `openURL`, `tapPoint` and `systemTap` (for
  permission sheets).
- `states` is the list of ways to capture it. A state can set the theme, the Dynamic Type size, the locale,
  the layout direction, the location, launch arguments and environment variables (and it can reset a
  permission first). See [States](Docs/Reference.md#states).
- `expect` is optional. It is an accessibility identifier the screen must carry, so a wrong screen is
  caught.

You do not have to write one by hand. `simwalk discover` crawls your running app to a bounded depth and
drafts a walkbook for you to edit. It taps only tab bar buttons, disclosure rows and the back button.

```sh
simwalk discover --app <bundle id> --lease <token> --output draft.walkbook.json
```

`--depth` (default 2) and `--max-screens` (default 25) bound the crawl. The answer lists every control it
did not tap, with the reason. See [Drafting a walkbook with `discover`](Docs/Reference.md#live-reads-and-sessions).

Check the walkbook without a device, walk it, then audit what it captured.

```sh
simwalk validate Fixtures/Settings/settings.walkbook.json
simwalk walk Fixtures/Settings/settings.walkbook.json --output run.simwalk
simwalk bundle audit run.simwalk
```

`validate` answers at once, from the file alone.

```
walk: 'apple-settings'  app: com.apple.Preferences  walkbook: d21ef61b  screens: 5  steps: 7
ok — 9 captures planned
  root — 1 step → [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl]
  general — 1 step → [light, dark]
  accessibility — 1 step → [light]
  display-text-size-lower — 3 steps → [light, dark]
  apple-account-sheet — 1 step → [light]
checked without a device — a route naming a control this build no longer renders still validates; only `walk` can catch that
```

`walk` took 38 seconds for the nine captures, with the app already built. This is what it said.

```
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 90b9fe86  device: iPhone19,3 (27.0)  animations: off  settled: 9/9
ok — 5 of 5 screens captured · 9 captures
  1 root — captured [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl] via scrollTo 'General'
  2 general — captured [light, dark] via tap 'General'
  3 accessibility — captured [light] via tap 'Accessibility'
  4 display-text-size-lower — captured [light, dark] via tap 'Accessibility' → tap 'Display & Text Size' → scrollTo 'Smart Invert'
  5 apple-account-sheet — captured [light] via tap 'Apple Account'
settle: the accessibility tree had to hold still for 250ms before each capture — animations it cannot see (chart draw-in, cross-fades, image decode) are not covered

accessibility: the XCUITest session switched com.apple.Accessibility AccessibilityEnabled off as it ended, and this walk switched it back on for <udid> and saw it hold — in-process accessibility suites on this device build their trees as before

animations: UIKit off in the app under walk (SwiftUI animations still run); --animations keeps them
result: ~/.simwalk/progress/<id>.result.json
~66k tokens saved — 9 screenshots (~4.1k each at the 2576 px cap) and 122 kB of accessibility trees at 4 bytes a token, against 1.5 kB served. A floor: only what this answer stood in for is counted.
```

- The first line says what was measured: the app and its build, the walkbook's hash, the runner that drove
  the app, and the device. `settled: 9/9` means the accessibility tree held still before all nine captures, so
  none was taken halfway through an animation.
- The second line is the verdict. `ok` means every screen was captured. If something needs your attention
  it starts with `qualified`, and names every reason.
- Then one line per screen, with the states captured and the route that reached it.
- The last line is the size. Those nine screenshots and 122 kB of accessibility trees came to 1.5 kB of
  text, about 66k tokens saved. The 1.5 kB answer costs less than one of the screenshots.

The walk wrote a capture bundle, the folder `run.simwalk`. It holds full-length screenshots stitched across
scrolling, the accessibility tree with the frame of each piece of text, and a manifest.
`bundle inspect run.simwalk` lists what is in it, and `bundle screen` prints one screen's text. Simulator
walks run with UIKit animations off, so a capture does not depend on an animation's phase; `--animations`
keeps them on ([Animations](Docs/Reference.md#animations)).

The audit then read the bundle without a device. Its output, trimmed:

```
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 90b9fe86  device: iPhone19,3 (27.0)  animations: off  settled: 9/9
qualified — 9 controls with neither a label nor an identifier; 8 labels shared by distinct controls on one screen; 1 control smaller than 44×44 points · audited 5 of 5 screens by 7 rules
…
[unlabelledControl] 9 found — 111 controls examined across 9 captures
  general:
    Image [light, dark] at y=166
…
[smallTarget] 1 found — 77 controls examined across 9 captures
  apple-account-sheet:
    Button 'Don’t have an Apple Account?' 229×33 pt [light] at y=379
```

`qualified` is SimWalk's word for "it worked, and something needs you". Here the audit found things in
Apple's own app, so the exit code is 2 (see [Exit codes](#exit-codes)).

## What else it checks

`simwalk bundle diff baseline.simwalk run.simwalk --crops crops/` compares two runs by structure and writes
a cropped PNG for each change. Run a walk before your change and one after, and the diff tells you which
sections moved, vanished or started to overlap.

![The same five rows of the demo app's Account screen at an accessibility text size, cropped from the baseline run (labelled before: each title above its value) and from the run with the regression (labelled after: each title drawn over its value), side by side.](Docs/Images/diff-crops.png)

`simwalk bundle oracle run.simwalk --walkbook app.walkbook.json` checks figures on screen against a program
you write that computes them. The walkbook needs `oracle` and `figures` entries. See
[The value oracle](Docs/Reference.md#the-value-oracle).

`simwalk bundle coverage run.simwalk` lists the controls no route step reaches, as the steps to add, so
you learn which parts of the app the walkbook never visits. It exits 2 when it finds any. See
[`bundle coverage`](Docs/Reference.md#bundle-coverage).

**Motion.** A screen with `"motion": true`, or a walk run with `--motion`, records how long the screen
took to settle and which elements shifted after first draw. Give a screen `budgets` (`settleMs`,
`layoutShifts`) and `simwalk bundle audit run.simwalk --walkbook app.walkbook.json` holds it to them with
the `motionBudget` rule, listing each shift's element and cause. `bundle diff` also flags a layout shift
present in one run only. See [Recording motion](Docs/Reference.md#recording-motion). `budgets` also take
`launchMs`, `transitionHitches`, `cpuMs` and `memoryPeakMB`, checked on a physical device.

**Preparing the device.** A walkbook's `setup` block grants or revokes privacy permissions, sets a clean
status bar and turns on Increase Contrast before the walk, and hands them back after. A state's
`resetPermissions` undoes a grant for one capture. See
[Preparing the device](Docs/Reference.md#preparing-the-device-with-setup).

`simwalk walk <walkbook> --output report.json --dry-run` follows every route and captures nothing, and says
`ok — 5 of 5 routes resolved · nothing captured` or names the route that broke. Run it after UI changes.
On the Settings walkbook it took 51 seconds.

`simwalk walk <walkbook> --output run.simwalk --parallel 4` shards the screens over four simulators at
once, and returns one bundle. The extra simulators are leased, or cloned from the walk's device; a clone is
deleted when the walk ends. Simulators only: a physical device is refused.

`simwalk bundle labels run.simwalk` reports what the walk's captures hold for the claims Apple's App Store
"Accessibility Nutrition Labels" ask about: Larger Text, Dark Interface, Sufficient Contrast and
Differentiate Without Color. Each claim comes back as holds, fails, incomplete or manual only, and an
incomplete claim names the state to add to the walkbook to finish it. If your app is in a sector the
European Accessibility Act covers, the report is evidence for that work. It is not a claim of conformance.
See [`bundle labels`](Docs/Reference.md#bundle-labels).

## In CI

`walk`, `bundle diff`, `bundle audit` and `bundle oracle` take `--junit <file>`, which also writes the
result as JUnit XML for a CI test reporter. `walk` writes one test case per screen and state.

The repository is also a GitHub Action. It walks your app on a macOS runner, diffs the walk against the
last one on the base branch, audits it, and posts the text answers as one pull request comment.

```yaml
- uses: actions/checkout@v4
- uses: Agulhas-Labs/simwalk@<tag>
  with:
    walkbook: walkbooks/main.json
    build-command: xcodebuild build -scheme MyApp -destination 'generic/platform=iOS Simulator' -derivedDataPath build
    app-path: build/Build/Products/Debug-iphonesimulator/MyApp.app
    fail-on: qualified
```

The job needs `pull-requests: write` and `actions: read`. See [GitHub Action](Docs/Reference.md#github-action)
for the inputs and [JUnit output](Docs/Reference.md#junit-output) for the file.

## Drive with anything, verify with SimWalk

SimWalk does not replace what you already use to drive an app. It checks what those leave unchecked.

- **Pixel snapshot tests** are good at catching a changed look. SimWalk adds a structural diff across
  runs that ignores new data and flags a missing section.
- **Screenshot-driving agents and simulator panes** are good at exploring an app by eye. SimWalk adds a
  declared state matrix, so every screen is captured in every state, and an accessibility audit reported
  across those states.
- **Flow runners** are good at scripting a path through an app. SimWalk adds a value oracle that checks the
  figures on screen, and leases that give each job a simulator of its own.

## For coding agents

`simwalk mcp` is an MCP server on stdio. It has eight tools for Claude Code: `walk`, `validate`, `inspect`, `audit`, `diff`,
`oracle`, `session` and `mirror`; a bounded client (any other) gets a ninth, `walk_status`. Each returns the same text as the CLI command of that name. The tools are
described in [Using SimWalk from a coding agent (MCP)](Docs/Reference.md#using-simwalk-from-a-coding-agent-mcp).

`simwalk inspect --app <bundle id>` reads the screen the app is on now, as text. This took 12 seconds, which
includes starting the runner.

```
live: app: com.apple.Preferences  runner: 7977d45f  device: iPhone19,2 (27.0)
ok — live read of com.apple.Preferences — root 'com.apple.settings.sidebar.collectionView', 19 text elements on screen
screen 3698a96b
Settings · StaticText · 16,120 133×41
Apple Account, Sign in to access your iCloud data, the App Store, Apple services and more. · Button · 16,168 370×90
General · Button · 16,293 370×52
Accessibility · Button · 16,345 370×52
…
text only — colour, shape and visual emphasis (a capsule vs. a line) still need a screenshot (xcrun simctl io <udid> screenshot <file>.png)
~3.6k tokens saved — 1 screenshot (~4.1k at the 2576 px cap), against 1.7 kB served at 4 bytes a token. A floor: only what this answer stood in for is counted.
```

Each line is the text, its type, and its position and size in points. The agent gets the layout without a
screenshot.

To explore step by step, `simwalk session start|read|step|save|end|list` keeps one runner resident on a
device. Reading the screen then takes about 0.4 seconds, because nothing starts up. `session step` performs
one route step and answers with the element it hit, the new screen's hash, and the lines that appeared
and disappeared. `session save` writes the route you found as a walkbook. See
[Live reads and sessions](Docs/Reference.md#live-reads-and-sessions).

`simwalk usage` reports what has been called, how long it took, what failed and why, and what the
answers saved ([Usage report](Docs/Reference.md#usage-report-simwalk-usage)).

## Real devices

`simwalk walk <walkbook> --output run.simwalk --device <udid> --team <team id>` walks a connected iPhone or
iPad. The team ID is the Apple signing team the runner is built under. `simwalk device` checks that a
phone can be walked, and `simwalk device clean` uninstalls the runner app from it. `simwalk lease acquire
--physical <udid>` reserves a phone so two sessions do not use it at once; `lease list`, `renew` and
`release` manage leases, and a plain `lease acquire` hands out a simulator of your own. Details are in
[Physical iPhones and iPads](Docs/Reference.md#physical-iphones-and-ipads) and
[Leases](Docs/Reference.md#leases).

`simwalk mirror` drives a real iPhone through macOS iPhone Mirroring and reads the screen as OCR text. Its
verbs are `read`, `tap`, `swipe`, `scroll`, `menu` and `burst`. It never types.

## Install

SimWalk runs on Apple Silicon Macs only, and needs Xcode. The walk runner is an XCUITest bundle. The
binary builds it from source with `xcodebuild` the first time a walk needs it, and pairs it with that
binary. That includes after an upgrade, with no step to re-run. SimWalk is tested on macOS 27.0.1 with
Xcode 27.1 and iOS 27.0 simulators. `mirror` needs a Mac with iPhone Mirroring.

Homebrew:

```sh
brew install agulhas-labs/tap/simwalk
```

Tarball: download `simwalk-<version>-<commit>-arm64.tar.gz` from the
[releases page](https://github.com/Agulhas-Labs/simwalk/releases) and unpack it where it will live. Put
`simwalk-<version>/bin` on your PATH, or symlink the binary from there. Keep the directory: the binary
builds its runner from the `share/simwalk` source beside it.

To use SimWalk from Claude Code, run `simwalk install-hook` once. A package manager never writes
`~/.claude`, so this step is yours. It is needed for agent use, not for the command line. It adds four
things.

- The MCP server, at user scope.
- A segment in the status line (`simwalk statusline` prints it; see
  [The status line](Docs/Reference.md#the-status-line)).
- A `PreToolUse` hook. In a repo that has walkbooks, it refuses some of the agent's own
  `xcrun simctl io … screenshot`, `simctl ui … appearance` and a third-party simulator CLI's `tap` calls,
  and points the agent at the `simwalk walk` that captures every screen instead. It never refuses the
  first such call in a context, refuses at most once per 30 minutes, and lets the same command through
  if the agent runs it again. The hook is `simwalk hook`, which the registration runs for you.
- An agent guide at `~/.claude/rules/simwalk.md`.

`simwalk uninstall-hook` removes all four (the MCP server only where `claude` is on PATH). For Claude Code
that is also how to switch the hook off, but there is no hook-only switch: the MCP server, status line and
guide go with it. The refusal is deliberate, a nudge toward a walk that captures everything. `simwalk prune`
removes walk-runner snapshots and builds no install uses any more, and reports the space freed;
`install-hook` runs it for you.

Without Claude Code, `install-hook` installs the runner, skips those four, and exits 2 to say so. For
another MCP client, such as Cursor, run `simwalk mcp` as a stdio server.

`simwalk install` does the same for every agent it finds, asking once per agent: Claude Code (exactly what
`install-hook` does) and Cursor (the MCP server in `mcp.json` and the `preToolUse` hook in `hooks.json`,
beside whatever else they hold). Codex is skipped. Without a terminal, pass `--yes` (every agent found),
`--all`, or `--agent claude|cursor|codex`. `install-hook` stays for Claude Code alone. No command removes
Cursor's entries: delete the `simwalk` entry from `.cursor/hooks.json` and `mcp.json` by hand. Afterwards
`install` runs the other Fieldwork tools' installs (sift) once, into the same agents, so one command sets
the family up. `--dry-run` shows what would change in each agent, and in the other tools, and writes nothing.

`simwalk doctor` then checks that each agent is wired end to end: the registration, the registered binary, each
hook fed a payload of that agent's shape, and the server's tool list, one line per check (`--json` for one
object, exit 1 on a failure). It checks Claude Code and Cursor; Codex is not checked. See
[Checking an install](Docs/Reference.md#checking-an-install-with-simwalk-doctor).

To build from source instead, see [Building from source](#building-from-source). That route needs a
Swift 6.2 toolchain; the package itself declares macOS 13 and iOS 17 as its floor.

## Exit codes

Every command exits 0 when the answer is clean. It exits 2 when the answer is qualified: it worked, and
something needs your attention, such as a screen it could not reach, a diff that found changes, or a
figure that did not match. It exits 1 when it refused. Gate CI on these. `simwalk mirror` also exits 3 when
the Mirroring window was not frontmost. Nothing was done, so retry.

## Limits

- iOS apps only, on simulators and connected iPhones and iPads. No macOS apps.
- HealthKit permission sheets cannot be granted ahead of time with `simctl`, so a route answers them with
  `systemTap`. Other permissions can be granted in the walkbook's `setup`.

## Documentation

- [Docs/Reference.md](Docs/Reference.md): every command and walkbook key.
- [SimWalk.md](SimWalk.md): the guide for coding agents.
- [Docs/SIMWALK-PROGRESS.md](Docs/SIMWALK-PROGRESS.md): the progress and result files a walk writes.

References like `SimWalk#N` in comments and docs point at the project's private tracker.

## Building from source

```sh
sh setup.sh     # once
swift build
swift test
```

`setup.sh` installs Homebrew if it is missing, then SwiftFormat and SwiftLint, and sets up the git hooks.

To install a build from source:

```sh
git clone https://github.com/Agulhas-Labs/simwalk.git && cd simwalk
swift build -c release
mkdir -p ~/.local/bin
rm -f ~/.local/bin/simwalk && cp .build/release/simwalk ~/.local/bin/simwalk
simwalk install-hook      # run from the repo root
```

Remove the old binary before copying the new one. Copying over it in place gets the new one killed on
launch with no message. `install-hook` pairs the binary with a snapshot of the walk runner from this
checkout, and a binary without one refuses to walk.

## License

Apache-2.0. See [LICENSE](LICENSE).
