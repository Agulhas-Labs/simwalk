---
paths:
  - "**/Walkbooks/**"
  - "**/*.walkbook.json"
  - "**/*.simwalk/**"
  - "**/*UITests/**"
---

# Using simwalk

`simwalk` drives a running iOS app through a **walkbook** on one device (a simulator or a physical iPhone or iPad) via XCUITest, and writes a
**capture bundle**: a screenshot plus an accessibility tree per screen per state, and a manifest of what
actually happened. **Prefer it over tapping by hand**: one ~2-minute call, reproducible.

| tool | call it for |
| --- | --- |
| `walk` | driving the app through a walkbook and writing a bundle |
| `validate` | checking a walkbook can be executed as written, in seconds |
| `inspect` | what a bundle reached, refused, and holds on disk; with `step`, one screen's own text |
| `audit` | rules over a bundle's trees (unlabelled controls, small targets, reading order, …); `walkbook` adds motion budgets (a screen's `budgets`) against the recorded motion |
| `diff` | one run bundle against a reference by form, never value |
| `session` | exploring a running app a step at a time (`start`, `read`, `step`, `save`, `end`, `list`) |
| `mirror` | a real iPhone through iPhone Mirroring (`read`, `tap`, `swipe`, `scroll`, `menu`, `burst`) |
| `oracle` | the figures a walkbook names, checked against its value oracle command |

Read this when:
- **Walking**: before any `walk` (time, output, devices, the settle reboot, the usage log).
- **Reading an answer**: before acting on a verdict or a screenshot. **Exploring live**: before a `session`.
- **If the tools aren't there**: no MCP tools, or no binary.

Walkbook authoring detail: if the repo keeps its walkbooks somewhere with a README, read it first; then SimWalk's
Docs/Reference.md ("Notes for writing walkbooks"). **Write `expect: "<identifier>"` on every screen
whose container carries an accessibility identifier**, or a route that left the app still records
`captured`. No identifier: omit `expect`; never copy the title.

## Walking

**A walk takes minutes and nothing comes back until it finishes**: that is the tool working, not a stall.
`output` must be a new or empty directory. **`dryRun: true` checks every screen's route still resolves, in
seconds per screen, capturing nothing**: run it after app changes, before a full walk.

While it runs, a walk writes `~/.simwalk/progress/<session>.json` (phase, step, timings); at the end, a
compact `<session>.result.json`, named on the answer's last residue line `result: <path>`. `verbose: true`
(`--verbose`) writes it whole: every state and route. Schema: SimWalk's `Docs/SIMWALK-PROGRESS.md`.

**Don't reboot the simulator yourself when a dark state draws light.** The walk refuses that state, settles
the device once (shutdown and reboot), and walks those screens again. **That settle reboots the device, so a
walk settles only a device it owns:** `--lease <token>`, `--device <udid>`, or one that was shut down until
the walk booted it. A device found booted and taken by name or as the default is never rebooted: the
refusals stand, the verdict is qualified, and the answer and the manifest's `appearanceSettle` carry the
settle to run. A settle reboots the device: anything attached (another session, a `log stream`, a debugger)
is cut off. **Beside other sessions, take a lease:**
`simwalk lease acquire [--clone-from <udid> | --physical <udid>] [--holder-pid <pid>]` hands back a device and a token, then
`walk --lease <token>` (`lease list|renew|release`, `--help`).

**Driving the binary for anything but real use (a test, a review, a probe of a refusal): set
`SIMWALK_USAGE_LOG=<scratch>/usage.jsonl`**, so the calls land in a log you own. **In a repo with
walkbooks, driving the simulator by hand** (`simctl io … screenshot`, `simctl ui … appearance`, a third-party simulator CLI's `tap`)
**is refused once per 30 minutes, never on a context's first such call** (that goes through, and so does its
re-run): the second, different call is refused, naming the `simwalk walk` that captures every screen instead;
for a one-off capture, run the simulator command it names again and it goes through. **For AX probing, read the tree instead of a
screenshot**: `simwalk inspect --device <udid|name> --app <bundle id> [--match <text>]` lists the running
app's screen identifier and text, launching and booting nothing.

## Reading an answer

- The verdict **is** the exit code: `ok` → 0, `qualified — …` → 2 (answered, every qualification named),
  `refused — …` → 1 (on stderr, with what would make it answerable). Treat 2 as an answer, not a failure.
  Don't pipe `walk` into `tail`: it reports tail's exit.
- Over MCP a refusal is an errored tool result reading `refused — …`; a *qualified* answer is not an error:
  read its verdict line.
- **Read the answer and the manifest before any screenshot.** A route that left the app records the wrong
  screen under a passing-looking outcome; the manifest shows it. Open a screenshot only for a flagged screen.
- **Read one screen's text with `bundle screen <bundle> <step>` (MCP: `inspect` with `step`) before opening
  `screen.png` or `ax-tree.json`.** Text only: visual form needs the screenshot. `--tree --match <q>` answers a
  node's identifier, frame, selected flag and ancestors, and `--bars` the bars' frames, instead of reading `ax-tree.json`.
- `diff`: open only the crops a flag names, not the screenshots.
- `settled: unrecorded` means the bundle predates settle recording — a declared gap, not a pass.
- It captures and reports; adjudication is yours.

## Exploring live

`simwalk session start --app <bundle id> (--device <udid> | --lease <token>) [--state <json>]` needs a
device you own (UDID or lease, never a name). **Sessions are for exploring; a walk stays the reproducible
record.** **Guard every step with the hash the last read or step printed**
(`session step <id> '<route step JSON>' --guard <hash>`): a changed screen refuses the step and does
nothing — read again. **Save before
`end`**, which deletes the session and route.

## A real iPhone

`mirror` is for a real device: **call it instead of screenshotting iPhone Mirroring.** Rules not to get wrong:
- **Fractions come from the answer's line boxes**: tap a line's centre x,y; never guess a position.
- **Scroll with `scroll`, not `swipe`**: a drag does not scroll inside an app. Positive lines reveal what is below.
- **Exit 3 means Mirroring was not frontmost: retry.** Nothing was posted before the action.
- **Read the PNG only when the pixels matter**; its path is in every answer. No text changed = a qualified answer.
- From the App Switcher, `menu home` takes two calls. It never types.
- **Never tap anything that deletes, signs out or disconnects**: it is a real phone.

## If the tools aren't there

The CLI answers identically: `simwalk validate <walkbook.json>`,
`simwalk walk <walkbook.json> --output <dir.simwalk> [--dry-run] [--lease <token>]`,
`simwalk bundle inspect|screen|audit|diff|oracle|coverage` (full listing in SimWalk's Docs/Reference.md).
If the binary is missing too, that is not a problem to report or fix mid-task. Run `simwalk uninstall-hook`
before deleting the binary.
