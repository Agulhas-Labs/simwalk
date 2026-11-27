# SimWalk

SimWalk is a regression check for an iOS app's whole UI, reported as text. After a change it visits every
screen in every display state (dark, large text, right to left, another language) and says which screens
changed shape or broke, in a few hundred tokens instead of a pile of screenshots.

![A recording of a SimWalk run: the Simulator on the left walks a demo app's Account screen in light, dark, large-text and Arabic right-to-left states, sped up six times; the terminal on the right then prints the structural diff against a baseline run, five overlap lines such as "Storage" over "{n} GB of {n} GB", beside the flagged crop before and after.](Docs/Images/hero.gif)

It is for an iOS developer whose coding agent edits views. The agent changes one view and cannot see the
other 29 screens; a screenshot of each costs it about 4k tokens and still has to be judged by eye. A walk
and a diff give it an answer it can read and act on. A team with an accessibility obligation and no QA
can use the same walk without an agent ([Accessibility](#accessibility)).

It needs a walkbook, a JSON list of your screens, which `simwalk discover` drafts for you. It pays back
from the second run on, when there is a baseline to compare with, so it suits an app of ten or more
screens under steady change. Your app needs no changes and no test target: SimWalk reads the
accessibility tree through XCUITest, from a runner of its own.

## Install

```sh
brew install agulhas-labs/tap/simwalk
simwalk install        # sets it up in Claude Code and Cursor; not needed for the command line
```

Apple Silicon Macs only, with Xcode. Tested on macOS 27.2.1 with Xcode 27.2 and iOS 27.0 and 27.2
simulators. A release tarball and a source build are in [Building](Docs/Reference.md#building).

## The proof

The repository's demo app has an Account screen and a switch that turns on a layout regression: each row's
title and value stop stacking at large text sizes. Walk it before and after, then compare the two runs
(`Fixtures/DemoApp/README.md` has the build and lease commands).

```sh
simwalk walk Fixtures/DemoApp/demo.walkbook.json --lease <token> --app-path $APP --output baseline.simwalk
# switch the regression on, as your change would
simwalk walk Fixtures/DemoApp/demo.walkbook.json --lease <token> --app-path $APP --output regression.simwalk
simwalk bundle diff baseline.simwalk regression.simwalk --crops crops
```

The diff's answer, with three of its eight flags and the crop file names trimmed:

```
bundle diff: run demo-app build 70ce4e06 against reference demo-app build 70ce4e06
qualified — 8 flags raised · 1 screen compared, 4 states
account/light-dt_uictcontentsizecategoryaccessibilityxl: 8 flags · screens/account/light-dt_uictcontentsizecategoryaccessibilityxl/screen.png
  overlap  row-title-0  "Storage" over "{n} GB of {n} GB" · run @16,182 370×516 → …5.png
  overlap  row-title-0  "Notifications" over "On, with previews" · run @16,182 370×516 → …6.png
  overlap  row-title-0  "English (United Kingdom)" over "Language" · run @16,182 370×516 → …7.png
  overlap  row-title-0  "Family, {n} members" over "Plan" · run @16,182 370×516 → …8.png
  overlap  row-title-0  "Backups" over "Daily at {n}:{n}" · run @16,182 370×516 → …9.png
~32k tokens saved — 8 screenshots (~4.1k each at the 2576 px cap), against 2.0 kB served at 4 bytes a token. A floor: only what this answer stood in for is counted.
```

![The same five rows of the demo app's Account screen at an accessibility text size, cropped from the baseline run (labelled before: each title above its value) and from the run with the regression (labelled after: each title drawn over its value), side by side.](Docs/Images/diff-crops.png)

Light, dark and Arabic are not mentioned because nothing changed there. The diff compares structure, not
pixels: which sections are there, in what order, whether text overlaps text. Numbers are read as `{n}`, so
new data is not a change, and a section that vanished is. `qualified` is SimWalk's word for "it worked,
and something needs you", and it exits 2 ([Exit codes](#limits-and-exit-codes)).

## Try it on Settings

This walks Apple's Settings app, so there is nothing of yours to build. The repository has the walkbook.

```sh
simwalk validate Fixtures/Settings/settings.walkbook.json      # checks the file, no device
simwalk walk Fixtures/Settings/settings.walkbook.json --output run.simwalk
```

The first walk builds the runner, which takes a few minutes. After that this walk takes one to two
minutes. Its answer, less four notes about settling and animations:

```
walk: 'apple-settings'  app: com.apple.Preferences  build: a35336d4  walkbook: d21ef61b  runner: 15545f49  device: iPhone18,3 (27.2)  animations: off  settled: 9/9
ok — 5 of 5 screens captured · 9 captures
  1 root — captured [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl] via scrollTo 'General'
  2 general — captured [light, dark] via tap 'General'
  3 accessibility — captured [light] via tap 'Accessibility'
  4 display-text-size-lower — captured [light, dark] via tap 'Accessibility' → tap 'Display & Text Size' → scrollTo 'Smart Invert'
  5 apple-account-sheet — captured [light] via tap 'Apple Account'
~36k tokens saved — 9 screenshots (~4.1k each at the 2576 px cap), against 1.5 kB served at 4 bytes a token. A floor: only what this answer stood in for is counted.
```

The first line says what was measured, and `settled: 9/9` that the screen held still before every
capture. A screen the walk cannot reach is reported as `UNREACHABLE` with the route it tried, never as a
capture of the wrong screen, and a state the device did not apply (asked for dark, drew light) is refused.
The walk wrote a capture bundle, `run.simwalk`: screenshots, the accessibility tree with each text's
frame, and a manifest. Every `simwalk bundle` command reads it without a device.

## Your own app

```sh
simwalk discover --app <bundle id> --lease <token> --output draft.walkbook.json
```

`discover` crawls the running app to a bounded depth, tapping only tab bar buttons, disclosure rows and
the back button, and drafts a walkbook for you to edit. Each screen in it has three keys that matter:

```json
{ "id": "general",
  "route": [{ "tap": { "label": "General" } }],
  "states": [{ "theme": "light" }, { "theme": "dark" }],
  "expect": "general-screen" }
```

`route` is the [steps](Docs/Reference.md#route-steps) from a fresh launch to the screen. `states` is the
[ways to capture it](Docs/Reference.md#states): theme, text size, locale, layout direction. `expect` is
optional: an accessibility identifier the screen must carry, so a wrong screen is caught.

## Accessibility

[`simwalk bundle audit run.simwalk`](Docs/Reference.md#bundle-audit) checks every capture by eight rules,
among them controls with no label, tap targets under 44 pt, reading order that does not match the layout,
and text that overflows or is truncated at accessibility sizes. On the Settings walk above, trimmed:

```
qualified — 9 controls with neither a label nor an identifier with VoiceOver off; 8 labels shared by distinct controls on one screen; 1 control smaller than 44×44 points; … · audited 5 of 5 screens by 8 rules
[unlabelledControl] 9 found — 101 controls examined across 9 captures
  general:
    Image [light, dark] at y=166
[smallTarget] 1 found — 68 controls examined across 9 captures
  apple-account-sheet:
    Button 'Don’t have an Apple Account?' 229×33 pt [light] at y=396
```

[`simwalk bundle labels run.simwalk`](Docs/Reference.md#bundle-labels) reports what the captures hold for
the App Store accessibility labels (Larger Text, Dark Interface, Sufficient Contrast, Differentiate Without
Color): each claim holds, fails, is incomplete or is manual only, and an incomplete one names the state to
add. For an app the European Accessibility Act covers this is evidence for that work, not a claim of
conformance.

## For coding agents

[`simwalk install`](Docs/Reference.md#installing-with-simwalk-install) sets SimWalk up in Claude Code and
Cursor, asking once per agent; Codex is not supported yet. It registers an
[MCP server](Docs/Reference.md#using-simwalk-from-a-coding-agent-mcp) (`simwalk mcp`, on stdio) whose tools
`walk`, `validate`, `inspect`, `audit`, `diff`, `oracle`, `session` and `mirror` return the same text as
the commands, an agent guide ([SimWalk.md](SimWalk.md)), and a hook. In a repository that has walkbooks,
the hook now and then refuses an agent's own simulator screenshot and points it at the walk that captures
every screen; the same command run again goes through. `simwalk doctor` checks the wiring and
`simwalk uninstall` removes it.

`simwalk inspect --app <bundle id>` reads the screen the app is on now as text, one line per element with
its type, position and size, and `--screenshot` adds the picture when colour or shape matters.

## Also

- **Figures.** `bundle oracle` checks numbers on screen against a small program of yours, so a total that
  is laid out perfectly and wrong is caught ([The value oracle](Docs/Reference.md#the-value-oracle)).
- **Sessions.** `simwalk session` keeps a runner resident for step-by-step exploring and saves the route
  you found as a walkbook ([Live reads and sessions](Docs/Reference.md#live-reads-and-sessions)).
- **Motion.** `walk --motion` records how long a screen took to settle and what shifted after first draw,
  and `audit` holds it to budgets you set ([Recording motion](Docs/Reference.md#recording-motion)).
- **CI.** `--junit <file>` on `walk`, `diff`, `audit` and `oracle`; the repository is also a
  [GitHub Action](Docs/Reference.md#github-action) that walks, diffs and comments on a pull request.
- **Real devices.** `walk --device <udid> --team <team id>` walks a connected iPhone or iPad
  ([Physical iPhones and iPads](Docs/Reference.md#physical-iphones-and-ipads)); `simwalk mirror` reads and
  drives one through iPhone Mirroring ([mirror](Docs/Reference.md#driving-a-real-iphone-with-simwalk-mirror)).
- **Simulators.** A [lease](Docs/Reference.md#leases) gives each walk, agent or CI job a device of its own;
  `--parallel N` shards a walk across several; `--slim` boots one without the services the app does not
  need ([Slim devices](Docs/Reference.md#slim-devices)); a walkbook's
  [`setup`](Docs/Reference.md#preparing-the-device-with-setup) grants permissions before the walk.

## Limits and exit codes

- iOS apps only, on simulators and connected iPhones and iPads. No macOS apps. React Native and Flutter
  apps are untried.
- It reads structure and text, not pixels: colour, shape and visual emphasis still need a screenshot.
- HealthKit permission sheets cannot be granted ahead of time, so a route answers them with `systemTap`.

Every command exits 0 when the answer is clean, 2 when it is qualified (an unreachable screen, a diff
that found changes), 1 when it refused, and 64 on a usage error. Gate CI on these.

## Documentation and licence

[Docs/Reference.md](Docs/Reference.md) has every command and walkbook key, and [SimWalk.md](SimWalk.md) is
the guide for coding agents. Apache-2.0; see [LICENSE](LICENSE).
