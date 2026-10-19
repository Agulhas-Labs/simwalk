# SimWalk reference

This file lists every command, every walkbook key and what each answer means. Read the
[README](../README.md) first for what SimWalk is and how to start. Come here when you need a detail.

- [What SimWalk does](#what-simwalk-does)
- [Reading an answer](#reading-an-answer)
- [What a walk checks before it files a capture](#what-a-walk-checks-before-it-files-a-capture)
- [The walkbook file](#the-walkbook-file): screens, motion, `expect`, states
- [Preparing the device with `setup`](#preparing-the-device-with-setup)
- [Checking a walkbook with `validate`](#checking-a-walkbook-with-validate)
- [Route steps](#route-steps): `tab`, `tap`, `type`, `scrollTo`, `tapPoint`, `openURL`, `back`
- [Tapping a point with `tapPoint`](#tapping-a-point-with-tappoint)
- [Answering system sheets with `systemTap`](#answering-system-sheets-with-systemtap)
- [Commands](#commands): every verb and its options
- [Walking a walkbook](#walking-a-walkbook), and a dry run
- [Devices and leases](#devices-and-leases), including physical iPhones and iPads
- [Reading a bundle](#reading-a-bundle): `inspect`, `screen`, `audit`, `diff`, `coverage` and [the value oracle](#the-value-oracle)
- [Live reads and sessions](#live-reads-and-sessions)
- [Usage report](#usage-report-simwalk-usage)
- [Notes for writing walkbooks](#notes-for-writing-walkbooks)
- [Driving a real iPhone with `simwalk mirror`](#driving-a-real-iphone-with-simwalk-mirror)
- [Using SimWalk from a coding agent (MCP)](#using-simwalk-from-a-coding-agent-mcp)
- [Installing with `simwalk install`](#installing-with-simwalk-install)
- [Checking an install with `simwalk doctor`](#checking-an-install-with-simwalk-doctor)
- [Installing with `simwalk install-hook`](#installing-with-simwalk-install-hook)
- [The status line](#the-status-line)
- [Building](#building)

## What SimWalk does

SimWalk checks what an iOS app shows by driving it for you. It works on a simulator or on a connected
iPhone or iPad. A visual check has four jobs: navigate, capture, compare and judge. SimWalk does the first
three the same way every time, so only the part that needs judging reaches a person or a model.

- **Walk and capture.** You describe screens, routes, themes, Dynamic Type sizes and locales in a JSON
  file, a walkbook. `simwalk walk` runs it through XCUITest and writes a capture bundle to disk: stitched
  full-scroll screenshots, the accessibility tree with text-run frames, and a manifest.
- **Compare two runs by structure.** `simwalk bundle diff` compares a capture against a reference and
  reports *form, never value*: sections present or absent, order, layout boxes, truncation, wrapping,
  overlap, degenerate charts. Each flag names the crop that shows it, so you open only the flagged crops.
- **Check figures against your own program.** `simwalk bundle oracle` matches every figure on screen
  against a value computed outside the app, under window rules you state. The program that computes the
  values is any command you name in the walkbook.
- **Give each run its own device.** `simwalk lease acquire` takes an exclusive lease on a device, so
  parallel sessions never walk the same one. A lease can clone a shut-down simulator (`--clone-from`) or
  hold a physical device.

SimWalk reports what is on screen. It does not decide what matters. That stays with whoever reads the
flagged part.

## Reading an answer

Every command answers in the same shape. Read the first two lines and you know what was measured and
whether to read on.

- **Line 1, the header,** says what the answer was measured against, as `key: value` pairs: the walkbook,
  the app, the build of it, the walkbook's content hash, the runner, the device, and how many captures
  were taken after the accessibility tree held still.
- **Line 2, the verdict,** is one word and a summary. `ok` exits **0**. `qualified` exits **2**: the call
  worked, and every caveat is named on the verdict line. `refused` exits **1**: the call could not be
  answered, and the reason goes to stderr with what would make it answerable.
- **`simwalk mirror` also exits 3** when iPhone Mirroring is not frontmost. Nothing was done, so you can
  retry (see [Driving a real iPhone](#driving-a-real-iphone-with-simwalk-mirror)).
- **The last line** says how many tokens the answer saved, on every answer that stood in for something (not `validate`). See below.

Exit 2 is an answer, not a failure. A screen SimWalk cannot reach is reported as UNREACHABLE with the
route it tried, never as an empty capture. A capture whose app build does not match the build you stated
is refused, rather than silently validating a stale binary. Every answer states its own arithmetic.

An UNREACHABLE line names the state whose route failed, since a route runs once per state and the
walk stops at the first failure:

```
  3. power — UNREACHABLE in state 'xxxl' (reached in light, dark; not tried: xxxl-dark), route tried: tab 'Workouts' > tap 'Power'; completed: tab 'Workouts'
```

A bundle that records no state prints `UNREACHABLE, route tried: …`.

The format is the one [Sift](https://github.com/Agulhas-Labs/sift) uses. Its
[answer contract](https://github.com/Agulhas-Labs/sift/blob/main/Docs/AnswerContract.md) is the
specification both tools answer to, so a reader who has learned to skim one has learned to skim the other.
After the header and verdict come the residue (what a reader has to look at, with nothing that is empty
printed as a heading, and the numbers that can go down before the counters that only rise). The last
line prices what the answer stood in for.

```sh
$ simwalk bundle inspect run.simwalk
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 7977d45f  device: iPhone19,2 (27.0)  settled: 9/9
ok — 5 of 5 screens captured · 9 captures
  1 root — captured [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl] via scrollTo 'General'
  2 general — captured [light, dark] via tap 'General'
  3 accessibility — captured [light] via tap 'Accessibility'
  4 display-text-size-lower — captured [light, dark] via tap 'Accessibility' → tap 'Display & Text Size' → scrollTo 'Smart Invert'
  5 apple-account-sheet — captured [light] via tap 'Apple Account'
settle: the accessibility tree had to hold still for 250ms before each capture — animations it cannot see (chart draw-in, cross-fades, image decode) are not covered

on disk — 3.1 MB across 5 screens
  root — 3 captures, 893 kB
  general — 2 captures, 559 kB
  accessibility — 1 capture, 305 kB
  display-text-size-lower — 2 captures, 1.1 MB
  apple-account-sheet — 1 capture, 225 kB
~64k tokens saved — 9 screenshots (~4.1k each at the 2576 px cap) and 114 kB of accessibility trees at 4 bytes a token, against 1.2 kB served. A floor: only what this answer stood in for is counted.
```

The header names the walkbook, the app, the build of it, the walkbook's content hash, the runner, the
device, and how many of the bundle's captures were taken after the accessibility tree held still (`3/3`, or
`1/3 (1 unrecorded)`, or `unrecorded` for a bundle that predates the runner recording it). What it does
**not** name is the run's timestamps or the device UDID: dates and machine names stay out of an answer.
Both are still in the manifest, which is the record.

A qualified answer names every qualification on the verdict line, before the counters:

```sh
$ simwalk bundle audit run.simwalk
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 7977d45f  device: iPhone19,2 (27.0)  settled: 9/9
qualified — 9 controls with neither a label nor an identifier; 8 labels shared by distinct controls on one screen; 1 control smaller than 44×44 points · audited 5 of 5 screens by 7 rules
[disclosureAffordance]
18 disclosure rows, every one typed as a control — consistent

[unlabelledControl] 9 found — 103 controls examined across 9 captures
  general:
    Image [light, dark] at y=166
…
[smallTarget] 1 found — 68 controls examined across 9 captures
  apple-account-sheet:
    Button 'Don’t have an Apple Account?' 229×33 pt [light] at y=396
…
~64k tokens saved — 9 screenshots (~4.1k each at the 2576 px cap) and 114 kB of accessibility trees at 4 bytes a token, against 2.1 kB served. A floor: only what this answer stood in for is counted.
```

A refusal is the same three words on stderr: `refused — cannot read …/ax-tree.json: missing key
'type' — this bundle is format 1 …`.

**The last line is a measured floor, not a headline.** The claim is that a reader
did not have to open the raw material, so the material is weighed and the answer's own cost subtracted
from it: every screenshot by its pixels (scaled so its long edge is at most **2576 px**, then one token
per 750 pixels, rounded up), every accessibility tree by its bytes at **4 bytes a token**, against the
byte count of the answer itself — the line you are reading and the newline after it included, which is
why `simwalk bundle inspect … | wc -c` reports the served figure exactly. `inspect` and `audit` charge
themselves with every screenshot and every tree in the bundle they answered about; a `walk` charges
itself with the bundle it just wrote. The constants are stated beside the figure because both are
conservative ends: an image read at full size costs at least what is claimed, and a JSON tree tokenizes
worse than prose rather than better. Nothing is modelled, nothing is extrapolated, and an answer that
stood in for nothing — a `validate`, which reads a file the caller already has — carries no such line at
all rather than claiming a saving of zero. `simwalk usage` adds them up over the log under the same
rule.

**Exit 2 means the call worked and the answer is qualified** — distinct from a refusal, because those
want different responses from a pipeline. `walk` exits 2 when the bundle is missing a screen the
walkbook asked for, holds a capture taken before the accessibility tree stopped changing, holds a
capture of the app's chrome with nothing under it, or survived a runner failure; `bundle audit` exits
2 when it found an inconsistency, when the bundle does not hold every screen its walk set out to
capture, or when what it does hold was captured before the accessibility tree stopped changing; and
**`bundle inspect` exits 2 over any bundle its verdict calls qualified**, including a bundle's shortfall
and its unsettled captures. The report is printed either way; the code is what a script gates on, and
it is read off the verdict word rather than recomputed beside it, so the two cannot disagree.

## What a walk checks before it files a capture

A walk does not trust that a route ran. It checks that the screen it filed is the one you asked for, and says so when it is not.

**An outcome names what was actually verified.** `captured` means the target screen was observed, not just that the route ran without
throwing, so a bundle never holds one screen's picture under another screen's id. Three checks
enforce it, none of them a timing assumption:

- **A step that navigates is waited on.** A `tap` returns the instant the touch lands, long before a
  push happens, and the screen it left then holds perfectly still — so the capture was of the screen
  the tap was leaving. `tap` and `back` are now landed only once the hierarchy's *structure* has
  changed from what it was before the tap, and report the screen UNREACHABLE if it never does. `tab`
  is the exception: a walkbook's first step routinely names the tab the app launched on, so a tab
  already selected is landed without being tapped (SimWalk#106: iOS pops a tab's stack to its root on
  a tap of the tab it is on, which would undo a screen a launch argument pushed). The tab is found in
  the tree, on a `TabBar` or on iPad's floating tab bar (a row of buttons, one selected; SimWalk#109);
  a tab neither holds is blocked naming the buttons that were seen.
  A `tab` whose button is in the tree but not hittable (a modal sheet over the app, SimWalk#95) is
  blocked before any tap, and says so, rather than landed.
  A `tap` that changes nothing lands when the step's destination is shown to be on screen already
  (SimWalk#125): the element is selected, in the snapshot and in a live read just before the tap, it is
  hittable then, and the tree read before the tap holds a navigation bar naming the label (its identifier
  or label, or a `StaticText` inside it). iPad Settings opens with the sidebar row General selected under a
  detail titled General. The bar is what shows the row's own screen is in front: a detail an earlier step
  pushed deeper keeps its own title, since reselecting a row does not pop it, and is refused. The tap is
  still made, unlike a `tab`'s. A selected element that is not hittable (a modal over the app leaves the
  selection true, #95) is refused as an unselected one is, and so is an already-active segment or filter
  pill, which has no bar naming it.
  A `tap` on a keyboard key (SimWalk#94) also lands if the keyboard-focused field's value changed, because
  a keystroke changes no structure; when it lands on neither, the refusal names both checks.
- **A screenshot is bracketed.** The picture is taken between two reads of the hierarchy and kept only
  if they agree, so a settled capture's screenshot and tree cannot be of different screens.
- **A spinner is not a screen.** A capture whose tree holds only the tab bar, navigation bar or
  toolbar — the app's frame and nothing of its own — is flagged rather than passed. That is a content
  check, so no machine is slow enough to defeat it.
- **A screen can state what it expects to find, and be held to it.** A route can complete, settle, and
  hold real content, and still not be the screen a walkbook believes it reached — the standing caveat
  below, one level up: `ScreenIdentity` catches a step that never left the screen it was taken on, not
  one that left and arrived somewhere else. A screen's optional `expect` names an accessibility
  identifier the reached screen carries (not the tab bar, toolbar or navigation bar); every capture it
  takes is checked against it, and a mismatch — including a capture carrying no screen identifier at
  all — becomes the screen's outcome (`unexpectedScreen`) rather than a note beside a passing one. Every
  capture is still filed: a wrong screen is evidence a reader needs to see, not a reason to hold nothing
  back.

**A stalled screen does not lose the bundle.** A recorded XCTest failure makes `xcodebuild test` exit
non-zero whatever `continueAfterFailure` says; the bundle is read back anyway, and a readable one is
the answer with the runner's failure named above it and the walk qualified. Only when there is no
bundle at all is the runner's own error the answer.

**A walk puts the device's accessibility back.** Every XCUITest session ends with `testmanagerd`
switching `com.apple.Accessibility AccessibilityEnabled` off, and SwiftUI builds no accessibility
elements for a hosted view while it is — so the next in-process accessibility suite on that
simulator fails for a reason that looks exactly like a code defect. A walk waits for that teardown
to land, switches it back on, confirms a few seconds later that it held, and says so in one line; if
it could not, the line carries the command that does it for the device that was walked, and the
verdict is qualified. Why this works where four earlier attempts did not — the key that actually
decides it, and the `defaults` that can actually see it — is recorded in the
`AccessibilityPreference` source.

**A state the device discarded is refused, not filed.** A walkbook asking for `dark` on a build of
iOS that reports the appearance set and changes nothing would otherwise file a light render under
`dark`, outcome `captured`, every format check passing — a passing bundle made of false evidence.
Two distinct states cannot have produced the same picture, so states that come back byte-identical
are refused, naming them; and a `dark` capture that is not measurably darker than the `light` one
beside it is refused on the same footing. **A refusal costs the states it names, not the screen**:
the light state beside an ignored dark one is still filed — when the device was found in light and
the light capture measures as a light render; the walk reads the device before it starts and puts it
back when it is done — the screen's verdict still says it was refused, and the manifest lists the
refused states so "refused on this device" never reads as "not reached". Where the evidence cannot
say which state is honest — an identical pair across an axis nothing measures, or a light capture
too dim to be told from a dark render — every state it touches goes.

**The two halves do not reach equally far, and this reference will not pretend otherwise.** Byte
identity is defeated by a status-bar clock advancing between two shots — measured on the very run
that was meant to demonstrate it — so it catches a discarded axis only when both captures landed
inside the same minute. `theme` has the brightness measurement behind it and is guarded;
`dynamicTypeSize` and `locale` have only the byte check, so on those two a silent discard is caught
opportunistically. A state's own `arguments` and `environment` have neither, by design: nothing can say
whether an argument reaches the screen, so a state differing from another only there and drawing the same
picture is filed as `identicalTo` it rather than refused. Both halves are one-way in any case: identity,
or a dark render that is not dark, proves a state did not apply — difference proves nothing.

## The walkbook file

A walkbook says which screens to walk and which states to capture on each one.

A walkbook is a JSON data file; `Fixtures/Settings/settings.walkbook.json` is a
worked example. A walk names an app and lists screens; each screen carries an `id`, a `route` from the
app's launch state, and the `states` to capture on arrival — plus an optional `settle` in
milliseconds, for a screen whose content streams in after the screen itself does, and an optional
`expect` naming an accessibility identifier the reached screen carries (not the tab bar, toolbar or
navigation bar) — or an `expectMenu` for a screen ending in an open menu:

```json
{ "id": "browse", "route": [{ "tab": { "label": "Browse" } }], "states": [{ "theme": "light" }], "settle": 6000, "expect": "browse-root" }
```

Per screen rather than per walk, because `--settle` is global and one slow entry would otherwise
triple a thirteen-screen walk. Omit it and the screen is timed by `--settle`, or by the 250ms default;
`validate` refuses a non-positive one rather than falling back in silence. Every screen that states its
own prints it on its line in the summary.

### Recording motion

Use motion when you want to know how long a screen takes to settle, or whether it shifts while it loads.

A screen may also say `"motion": true` (or a walk run with `--motion`, every screen; the MCP `walk`
tool's `motion`) to record, on each of its captures, a `motion` record: `settleMilliseconds`, how far into
the watch before the capture the tree last changed (the read that first showed the captured tree);
`readIntervalMilliseconds`, the 250 ms pause between those reads and so the figure's resolution (reads are at least that far apart, each one's own cost on top); and
`readCount`. A capture whose watch ran out of budget unsettled records no `settleMilliseconds`, only the
cadence and the count. A change that comes and goes between two reads, or an animation the tree cannot
see, is not in it. A capture without the record means motion was not recorded, never that there was none.
Three more keys (SimWalk#67):
- `shifts`: each layout shift seen, as the element's identity, its box before and after, when it moved (ms) and its cause. Absent means shifts were not recorded; `[]` means none were seen.
- `landingMilliseconds`: from the last step's action returning to the arrival read, the first read in which the screen it was taken on has been left. That is the first structural change, so for a push it times when the new screen starts to arrive, not when its slide finishes. Absent with no route, and for `type`, `scrollTo`, `tapPoint`, `systemTap` and an already-selected tab.
- `measuredReadSpacingMilliseconds`: the median gap between reads, which is the cadence as measured and not as asked for. A median, because the screenshot bracket read has no pause before it and one slow read would skew a mean.

A shift is a matched element whose box moved by at least 1 pt while, in the same pair of reads, something else was inserted, removed or resized in line with it: inserted or grown on the side it moved away from, or removed or shrunk on the side it moved towards, clear of it along that line and in the same column or row. The nearest such change is named as the cause. That condition excludes push slides and a `systemTap` sheet (a sheet overlaps what it covers, so it is never a cause). An app's own scroll is not a shift: when all of a scroll container's content that moved, moved by one offset relative to the container (a section header pinned in place does not count against it), it scrolled, even where a lazy list built and dropped rows at its edges, unless a change inside the container has exactly that extent (an inserted or removed box plus the gap to its matched neighbour beyond it, an inserted box also plus the gap before it, or a resize's growth; never a box alone, which a scroll's step would match against the height of some row, or icon, a lazy list built meanwhile, as a banner arriving at the top of a list does), or an insertion and a removal starting at one place differ in length by it (a loading text replaced by a taller header; their own lengths, so a label changing in place mid-scroll is no cause, and a replacement whose gap below changed too is missed). Two scrolls read as shifts: an app scrolling a lazy list of uniform rows by exactly a whole number of rows (their insertion or removal), and a pinned section header handed over by the next one mid-scroll. A displacement inside a scroll container that no single change or replacement has the extent of reads as a scroll and is missed. After a `scrollTo` or `systemTap`, a move inside a scroll container that matches the offset most of it moved by is excluded too. Elements pair top-down, children only under a paired parent, by type, identifier and label, and an anonymous element by its type and the first label or identifier it holds, or, where that is shared (rows beginning with one icon), every name it holds in order; the roots always pair, and so does an anonymous sibling that is the only one of its type in both reads (the window, whatever the screen's first label became). A group of siblings that does not pair one-to-one is left out rather than guessed, as are rows that begin alike when one's own text changed (a row whose first name changed, an icon swapped, reads as a removal and an insertion). Only labelled or identified elements are reported, and a descendant moving with a reported ancestor is folded into it. Tree paths are `[Int]` from the root: a shifted element's, and an inserted or resized cause's, in the later read; a removed cause's in the earlier. Keyboard avoidance is reported (a pinned button moving with cause `resized ScrollView`); `bundle diff` compares a shift's presence across bundles, which keeps a consistent one from flagging. The cost is that a displacement whose cause is not in the tree is missed, and so is a shift that comes and goes between two reads, and one whose insertion is read at its final box while what it pushes is part way along (inside a scroll container that reads as a scroll); two live walks of the banner fixture never read rows mid-slide, so accessibility frames appear to be the model layer's.

A screen may state `"budgets": { "settleMs": 1500, "layoutShifts": 0 }` (SimWalk#67): the most milliseconds its tree may take to settle and the most layout shifts it may show. Four more keys bound a physical-device walk's performance: `launchMs`, `transitionHitches`, `cpuMs` and `memoryPeakMB`. Each key is optional, but an empty object, a negative figure and an unknown key are refused by `validate`. A screen with budgets records motion without `"motion": true`. `bundle audit --walkbook` holds the recorded motion to them (the `motionBudget` and `performanceBudget` rules, under `bundle audit`); the walk itself checks nothing.

`--motion` beside `--dry-run` is refused: a dry run captures nothing. The `session` verb records none.

### Animations

A simulator walk launches the app with UIKit animations off, so screens settle sooner and a capture does not
depend on an animation's phase. `--animations` (the MCP `walk` tool's `animations`) keeps them on, and so does a
walk that records motion: `--motion`, or any executed screen that says `"motion": true` or states a motion
budget (`settleMs`, `layoutShifts`), because motion and settle time must match what users see. A screen left out
by `--screens` does not count. SwiftUI `withAnimation` is not affected. A walk has one animation state, so a walkbook state's `environment`
cannot set `SIMWALK_ANIMATIONS` (`validate` and `session start --state` refuse it: `a state's environment cannot
set SIMWALK_ANIMATIONS: a walk has one animation state; run it with --animations to keep animations on`). A
physical-device walk is unchanged, and
`--animations` there changes nothing. The answer says which applied: `animations: UIKit off in the app under walk
(SwiftUI animations still run); --animations keeps them`, or `animations: kept on, because this walk records
motion`. A library that cannot be built fails the walk, naming the reason and `--animations`.

`simwalk session start` does the same for a simulator session (the app the resident runner launches, with or without
`--state`): UIKit animations are off unless `--animations` (the MCP `session` tool's `animations`, on `start`) is
passed. A session has no motion recording, so only that flag keeps them. A physical-device session is unchanged and
`--animations` there changes nothing. The header of the start's answer ends `animations: off` or `animations: on`
(a device session says `on`). A library that cannot be built fails the start before the device is touched.

The bundle records which applied: the manifest's `animations` (`on` or `off`, written by the runner; absent in a
bundle written before SimWalk recorded it, which ran with animations on, and a device walk records `on`). The
header of every bundle answer shows it between `device:` and `settled:` as `animations: off`, and shows nothing
for a bundle that does not record it. `bundle diff` refuses a reference and a run captured in different states,
because their motion and settle figures differ for that reason alone: `bundle diff refused: the reference was
captured with animations on and the run with animations off, …; capture both in one state (--animations keeps
animations on, and a walk that records motion or runs on a device keeps them on regardless)`. An unrecorded bundle counts as on, and the refusal says so. The field sits inside format 8:
the manifest's top level decodes leniently, so no bump is taken.

### Slim devices

A device `simwalk lease acquire --clone-from` created boots slim when the walk runs under that lease (`--lease`) and names the app with `--app-path`: the launchd services the app does not need are switched off, which makes the boot and the walk cheaper. What the app needs is read from the entitlements and `Info.plist` of the `.app` (HealthKit, push notifications and the like keep their services); an app that declares something no rule maps, a runtime with no measured service profile, or a bundle that cannot be read boots stock, and the answer says why. Animations are not touched; only launchd services are.

The walk's answer carries one line: `device: slim: 94 of 338 services off (iOS 27.0, profile v1), kept for the app: healthKit 5`, checked by reading the switched-off services back from the booted device (`device: not slim: …` when the runtime did not apply the switch-off, `device: slim, unverified: …` when the read-back itself failed; neither fails the walk), or `device: stock: <why>`. A walk with neither `--app-path` nor `--stock` decides nothing and boots a device as it is, so a slim device stays slim across walks. A device SimWalk did not create is never slimmed.

`--stock` (the MCP `walk` tool's `stock`) boots such a device with every service on, shutting it down first if it is booted with services off. On a device SimWalk did not create that has services off it is refused, because only its creator can switch them back on; with none off it changes nothing. It is refused for a physical device. Releasing a device SimWalk created removes its override along with the device.

### Checking the screen with `expect` and `expectMenu`

Use `expect` when a route could finish on the wrong screen. It names an identifier the right screen carries.

`expect` is opt-in and checked exactly, never against a leading component the way a route step's label
is: every capture the screen takes must carry it as any screen-level identifier, outermost or nested (a
screen hosted inside another's content carries both, SimWalk#103) — wherever
the app set it in the tree, never on the `Application` root, which carries none — so a screen that lands
right under `light` and wrong under `dark` cannot pass by averaging. What never counts is chrome, because
it sits on every screen: anything inside the tab bar, toolbar or navigation bar (a tab item's SF Symbol
name, `BackButton`, `Toolbar`, **and the navigation bar's own title**), an element's own identifier (an
image's symbol, a button's), and SwiftUI's mangled `_Tt…` class names. A title is localised and not
unique, so an `expect` naming one would pass under `light`, fail under a `loc_fr_fr` state, and pass on
any other screen with the same title; when a mismatch's `expect` is the screen's title, the walk says so
and asks for an identifier on the content instead. `validate` refuses an `expect` stated as an empty
string, padded, or spelled like a mangled Swift name — none of them could ever pass. A capture carrying
no screen identifier at all counts as a mismatch rather than a pass: the check is opt-in exactly where an
app has adopted the convention of setting one, and passing silently when it finds nothing would be the
same discard this key exists to end.

`expectMenu` (SimWalk#111) checks a route that ends by opening a SwiftUI system `Menu`, which `expect`
cannot: the open menu hides the screen's identifier and has none of its own. It lists the labels the open
menu must show, in order — read top-down or bottom-up, since iOS lists a menu's items nearest the
control that opened it first and one opening upwards reads reversed — and what it proves is that those labels are on screen as buttons, not that a menu
is open — so pick labels the screen beneath does not also carry as its own buttons (a segmented picker of
the same kinds would pass with the menu closed); every capture's `Button` nodes (an open menu's items are `Button`s in a
`CollectionView`; there is no `Menu` node type) must hold them as an ordered subsequence, each matched
exactly, other buttons allowed between:

```json
{ "id": "goal-menu", "route": [{ "tab": { "label": "Goals" } }, { "tap": { "label": "Goal type" } }], "states": [{ "theme": "light" }], "expectMenu": ["Endurance", "Walking", "Strength (usual)"] }
```

A mismatch is the screen's `unexpectedScreen` outcome: `expected 'menu: Endurance, Walking, Strength (usual)'`,
`found` the capture's first screen identifier (so `found [goals-screen]` reads as "the menu did not open"),
and a reason naming the first label not found in order and the Buttons the capture holds (the first 8).
`expect` is unchanged and checked on its own; since an open menu hides the screen's identifier, `expect`
beside `expectMenu` normally fails, so state one or the other. When both mismatch, `expect`'s expected and
found lead and the menu clause rides in the reason. `validate` refuses an `expectMenu` that is empty or
holds a blank or padded label.

### States

A state is one way to capture a screen: a theme, a text size, a locale and so on.

A state is a `theme` (`light` or `dark`) plus any of seven optional conditions:
`dynamicTypeSize` (a `UIContentSizeCategory` name), `locale`, `layoutDirection`, `location` and
`resetPermissions` (below), and — for a screen an app shows only under
a launch argument (SimWalk#44) — `arguments`, a list of strings the app is launched with after the ones
the other axes become, verbatim and in order, and `environment`, an object of variables laid over the
launch's own, the state's value winning. An app's own `--seed-data` launch argument can raise HealthKit's
write-authorization sheet, and the route answers it:

```json
{ "id": "health-access", "route": [{ "systemTap": { "label": "Turn On All" } }, { "systemTap": { "label": "Allow" } }], "states": [{ "theme": "light", "arguments": ["--seed-data"] }] }
```

Each state is filed under a slug built from its axes in order — `light`, `dt_…`, `loc_…`, then `args_<h>`
and `env_<h>`, where `<h>` is the first 8 hex characters of a SHA-256 over the arguments in order (or the
environment's pairs sorted by key), each part length-prefixed rather than joined with a separator, so
`-a b` and `-a_b` never share a directory and an environment key holding `=` cannot be mistaken for its
value; the manifest's `state` carries the exact list. `validate` refuses an empty `arguments` list or an
empty `environment` object (omit the key), an empty argument, and an empty variable name — an empty
variable *value* is a legitimate setting (`FOO=`) — and checks nothing else about them, since what an
argument means is the app's.

Three more axes follow, each held to what its capture shows rather than to the API that set it:

- **`layoutDirection`** (`"rtl"` or `"ltr"`, slug `-rtl`/`-ltr`) launches the app with both
  `-AppleTextDirection` and `-NSForceRightToLeftWritingDirection` — on iOS 27 neither alone mirrors a SwiftUI
  `HStack`. The tree keeps declaration order and only the frames mirror, so the check reads frame `x` along
  tree order over each row of siblings: a capture whose every judged row runs the other way is refused
  (`stateNotApplied`), and one with no row to judge is filed with `unverifiedAxes: ["layoutDirection"]`.
- **`location`** (`{"latitude": 51.5, "longitude": -0.12}`, slug `-geo_<h>`) is set on the simulator
  (`XCUIDevice.location`) before that state's launch; a state without one walks under whatever the device
  was simulating when the walk began, and the walk puts that back at the end. It is verified only when a
  number on the screen rounds to each coordinate at the precision printed; otherwise it is filed
  `unverifiedAxes: ["location"]` — a screen not showing where it is proves nothing, so it is never refused.
- **`resetPermissions`** (`["location", "camera"]`, slug `-reset_<h>` over the names de-duplicated and
  sorted) resets the app's grant for each named resource (`resetAuthorizationStatus(for:)`) after the
  previous state's app is terminated and before this one launches, so a route that answers a permission
  sheet with `systemTap` finds it on every walk, not only the first. The names are `XCUIProtectedResource`'s
  iOS cases — `contacts`, `calendar`, `reminders`, `photos`, `microphone`, `camera`, `mediaLibrary`,
  `homeKit`, `focus`, `localNetwork`, `bluetooth`, `keyboardNetwork`, `location`, `health`, `userTracking`;
  `validate` refuses any other with the nearest one, and an empty list. The walk does not restore a grant it
  reset, and its summary names each one; whether the app is asked again depends on whether the route's own
  `systemTap` granted it back.

An unverified axis is a qualification on the walk's summary and on `bundle screen`, never silence.

## Preparing the device with `setup`

Use `setup` when a walk needs the device in a known condition before it starts, such as a permission granted or a clean status bar.

**A walk-level `setup` block** prepares the device on the host before the runner starts, and hands it
back after — on a refused walk too:

```json
"setup": { "privacy": { "grant": ["location"], "revoke": ["contacts"] }, "statusBar": "clean", "increaseContrast": true }
```

- **`privacy`** runs `simctl privacy <udid> grant|revoke <service> <appBundleID>`; the services are
  `simctl`'s own on iOS 27 (`calendar`, `contacts-limited`, `contacts`, `location`, `location-always`,
  `photos-add`, `photos`, `media-library`, `microphone`, `motion`, `reminders`, `siri`; `all` is refused,
  since a manifest could not name it back). A route then reaches a screen behind a permission sheet with
  no `systemTap`. The handback resets each service: the prior grant is not restored. HealthKit is not a
  `simctl` service, so Health stays `systemTap`; a per-state `resetPermissions` of the same resource undoes
  the grant.
- **`statusBar: "clean"`** overrides the status bar (9:41, full bars, charged) and sets it again after an
  appearance settle's reboot, which clears it; the handback clears it. Recorded as set and unverified: the
  app's tree does not carry SpringBoard's status bar.
- **`increaseContrast`** sets Increase Contrast and puts back the value it found; recorded as set and
  unverified, since nothing captured reports it.

Setup changes device-wide state, so it is refused on a device the walk does not own (named by UDID,
leased, or booted by the walk) before anything is touched. A dry run makes it and hands it back too. The
manifest's `deviceSetup` records what was made and handed back, and `bundle inspect` prints it.
`Fixtures/RouteFixture/states.walkbook.json` walks all three against the route fixture.

## Checking a walkbook with `validate`

`simwalk validate <walkbook.json>` reads a walkbook and checks that it could be walked as written. It needs no device, so run it after every edit.

```sh
$ simwalk validate settings.walkbook.json
walk: 'apple-settings'  app: com.apple.Preferences  walkbook: d21ef61b  screens: 5  steps: 7
ok — 9 captures planned
  root — 1 step → [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl]
  general — 1 step → [light, dark]
  accessibility — 1 step → [light]
  display-text-size-lower — 3 steps → [light, dark]
  apple-account-sheet — 1 step → [light]
checked without a device — a route naming a control this build no longer renders still validates; only `walk` can catch that
```

**An unrecognised key anywhere a walkbook author writes one is a `validate` refusal, not a silent
drop (SimWalk#10).** `{ "theme": "light", "textSize": "accessibility5" }` would otherwise capture the device's
default size and file it under a slug asserting `accessibility5`, with `walk`
reporting `0 state-not-applied`, since nothing asked the runner to apply an axis it never saw. The
walk, every screen, every state and every route step (its case name and its own payload,
`{"tab":{"label":...}}` and its siblings) now refuse a key they do not recognise, naming it and the
nearest one they do — `textSize` names `dynamicTypeSize`, not `theme`, because the check weighs the
longest word the two share before it counts single-letter edits — and offering nothing where nothing is
close. `expect` written on a step is told it belongs on the screen. Every such key is listed in one
refusal beside every other problem, and nothing stops the listing short: a misspelled *required* key
(`"them"` for `theme`) is named beside the key it leaves missing, and a misspelled step (`"tabb"`) beside
the step it leaves unnamed, and both are read past so every later problem is listed too. A value of the
wrong type (`"theme":"purple"`) has no placeholder to stand in, though, and still stops the decode there
— what was collected before it is listed, but nothing after. What a
placeholder stands in for is never checked as though it were written — but only its own corner is
skipped: one screen's checks when the placeholder sits inside it, or the walkbook's own `name`,
`appBundleID` and `screens` when it sits at the top level. Every other screen's problems are listed
exactly as they would be alone, and the refusal names exactly which checks did not run. A `tab` step
naming `{n}` is refused: a tab is looked up by its name as it reads, so the placeholder could never match
— `{n}` is resolved for `tap`, `scrollTo` and `type`, never for a tab's exact label.

## Route steps

A route is the list of steps that takes the app from its launch state to a screen. This section lists the steps and says how each one finds its element.

Route steps — every label is the **accessibility label**, the thing an author can see on screen, and a
leading comma-separated component counts as a match so a row's live trailing count cannot rot a route.
Where a label carries data with no comma before it, write **`{n}`** where the number goes: `'Sailing {n}'`
reaches the filter chip `Sailing 22` whatever its count reads, and matches the whole label — the rest must
match to the letter, and `{n}` stands for one number (`22`, `1,234`, `3.43`, `3,43`, `+0.62`, `−0.62`) —
decimal digits in any script (`٢٢` too, but not `²`, `½` or `五`), joined only by a `.` or a `,`. A number
grouped by a space (`4 210`, as French draws it), an apostrophe (`4’210`) or the Arabic separators (`٣٫٤`)
is not read as one, and the step finds nothing. The placeholder is
opt-in on purpose: a bare `'Sailing'` keeps meaning what it meant, which on a list screen of passages is
the *By sport* row `Sailing, …`. It is also a tier below every literal match: `'Week {n}'` still reaches an
element whose label really reads `Week {n}` (or starts `Week {n}, `) wherever `Week 3` sits, and an element
the pattern reaches is taken only once the step's lookup (10 s) has run out with nothing literal found — so
a literal match arriving at any point before that still wins, and **a `{n}` step takes the whole lookup**,
by design. `tab` looks tabs up by name and does not read `{n}`:

| step | JSON | what it does |
| --- | --- | --- |
| tab | `{"tab":{"label":"Progress"}}` | select that tab |
| tap | `{"tap":{"label":"Heart"}}` | tap that element; a label nothing on screen carries yet is swiped towards first, as `scrollTo` does (SimWalk#104) |
| type | `{"type":{"label":"Search","text":"resting"}}` | tap that field and type into it |
| scrollTo | `{"scrollTo":{"label":"Rows"}}` | swipe until that element is on screen, then nudge it clear of any tab bar, toolbar or navigation bar in front of it (SimWalk#108) |
| tapPoint | `{"tapPoint":{"label":"Steps chart","at":[0.8,0.5]}}` | tap a point within that element's frame, as fractions of it |
| tapPoint | `{"tapPoint":{"at":[201,610]}}` | tap a point on the screen, in device points |
| systemTap | `{"systemTap":{"label":"Allow"}}` | tap a control on a system permission sheet or alert, SpringBoard's first, then the app's window; `"atLaunch":true` on a route's first step declares that the launch raised the sheet |
| openURL | `{"openURL":{"url":"myapp://detail"}}` | open a URL in the app (`http`/`https` through the system); lands only if the screen changed, so a URL the app does not route is UNREACHABLE |
| back | `{"back":{}}` | navigate back one level |

Note `back` takes an empty object like every other step, not the bare string `"back"` — the whole
vocabulary is written the same way, and each row above is pinned by a test against the encoder.

### Which element a label reaches

**When more than one element carries a `tap` label, the one that can navigate wins** (SimWalk#17): a
button, cell, link or switch in the screen, above one inside a navigation bar, tab bar or toolbar (so a row
`Workouts, 18` beats the tab item `Workouts`, and a toolbar's `Edit` still beats a text `Edit`), above
static text and images, above the bars themselves and anything disabled; then a whole label or identifier above a leading component. A
label that differs from the step's only by a no-break (U+00A0) or narrow no-break (U+202F) space where the step has a
space (`'CO₂ level'` against `CO₂ level, 38.8 …`; read as a space on both sides, identifiers excluded) is considered only
when nothing matches byte for byte, and ahead of a `{n}` pattern; the refusal says the label has a no-break space
(SimWalk#99). A `{n}` pattern is considered only when nothing carries the label in any of those ways, whatever kind it is. Among
equals the first in tree order is taken, so `tap 'Coastal Cruise'` on a list of passages reaches the newest.

**A `tap` whose label resolves to nothing swipes up and reads again, as `scrollTo` does** (SimWalk#104): one route has
to work across a screen's states, and Dynamic Type moves rows below the fold of a lazy list, where the element is
not in the tree at all. The swipes share `scrollTo`'s budget of twelve and its refusal (`nothing on screen is labelled
or identified 'X': swiped up N times and the last swipe moved nothing …`). Only a label that matches nothing seeks: an
ambiguous one is refused as before, and `type` does not seek. The manifest still records the step as `tap`.
A row the seek brought into the tree sits at the fold, under the tab bar a tap there would land on, so a `tap` that
swiped is nudged clear of the bars in front of it as a `scrollTo` is before it taps, and refused with the same reason
where it cannot be (SimWalk#104, #108); a `tap` that did not swipe is unchanged.
A screen titled `Sleep` no longer hands `tap 'Sleep'` to its navigation bar: the row labelled
`Sleep, Nothing earlier to compare with` is the answer, whatever its note reads on a given store. A tap
that still does not land comes back UNREACHABLE saying what it tapped and what else its label matched.

**Only when nothing matches in any of those ways** — literally or by a `{n}` pattern, as a control, as
content, or even as chrome — is a label that merely *starts* with the step's text considered, and only if
what follows is data: separators (whitespace or a `·`) and then a decimal digit. So `'Sail, 12 August'` reaches
`Sail, 12 August 14:50 · 3.43 km, 12 min`, while `'Wind'` never reaches `Windward, …` or
`Wind (kn)`, `'Distance 3'` never reaches `Distance 3.43 km`, and `'Steps 4'` never reaches `Steps 4,210`
— nor `Steps 4 210`, grouped by a space. A comma is not a separator, since a comma and a space already end a
leading component and any other comma before a digit is inside the number; neither is a non-breaking, narrow
or thin space between two digits, which is how French, Russian or Swedish group a number. A lead-in is held
to more than the other matches: two it reaches equally are refused by name rather than guessed between (an
element and anything inside it carrying the same label count once), and it is acted on only once the step's
lookup (10 s) has run out with nothing literal found — so **a lead-in step takes the whole lookup**, by
design, and a row matching outright that arrives at any point before that wins.

**A `{n}` match or a lead-in never takes a step away from an element it reached before** — not on one
screen, and not by acting sooner: each is consulted only where nothing matches literally, and acted on only
at a moment the step used to report UNREACHABLE. What a `tap` matched literally it still reaches, at the same
moment, with one exception #24 makes on purpose (below): a bar's control on a screen that has held still is
taken after the quiet period, so a row that arrives after that loses to it.

**Which element a label step bound** (SimWalk#93): a screen record's `boundElements` lists, for each landed `tap`, `scrollTo` and `type` step, `{step, type, identifier, label, frame}` — `step` indexes `routeTaken`, the frame is the snapshot's. Absent means a bundle that does not record it; `[]` means the route bound nothing. It is a sibling list, not a field on a `routeTaken` step, so the bundle stays in format 8.

### Waiting and scrolling

A tap whose best match is a control inside a bar (a toolbar's `Edit`) is taken once the tree has held still
for the quiet period of the screen the step is taken on, rather than after the rest of the budget: a row still
loading would change the tree. The screen a step is taken on is the walkbook entry whose route is exactly the
steps before it, and its quiet period is that entry's `settle`, or `--settle`; a route's first step, and a step
on a screen the walkbook does not name (or a `--screens` subset left out), is timed by `--settle`. The
destination's `settle` times its capture, not the steps on the way to it. `scrollTo` and `type` match their labels the same way
as `tap` — the same tiers, `{n}` and lead-ins included — but reach for different things, so `scrollTo X`
and `tap X` do not always arrive at the same element. A `scrollTo` never prefers a tab item or another bar
control to content (a bar is always on screen, so it would land without scrolling): `scrollTo 'Workouts'`
goes to the card and `tap 'Workouts'` to the tab item. That holds only while the card is in the tree — a
lazy list that has not built it yet leaves the tab item as the only match, and the scroll lands on it
without scrolling, as it always did. A `scrollTo` arrives at content or a control its label names literally
the moment it exists, as it always did; it waits for the screen to hold still only when all it has found is
a bar's control or chrome, and a `{n}` match waits for the lookup as a tap's does. Once it has arrived, a `scrollTo` nudges the content until the element's frame clears every tab bar, toolbar and
navigation bar that overlaps it and is in front of it (SimWalk#108: XCUITest calls an element hittable while the iOS 27
floating tab bar is over half of it). In front means hittable live: a modal can leave the tab bar of the screen it
covers in the tree (SimWalk#95), and that bar does not count. A bar in the lower half of the screen (a tab bar, a
bottom toolbar) moves the content up, one in the upper half (a navigation bar) down, wherever in its band the element
sits. Each nudge is a slow drag at the element's own x; a drag that moved nothing is tried again at twice its length,
and every later nudge of the step is doubled too, so the step is UNREACHABLE, naming the bar, only where a doubled drag
moved nothing or three nudges were not enough. An element taller than the room between the bars is accepted, and so is one that is a bar or sits in
one — a tab item, a navigation bar's button — which no scroll moves out from under its own bar. After every swipe it checks
that what it bound still carries the label it chose, at the same size, before it counts as arrived. A `type`
considers only fields that take text, and refuses, naming both, when its label names fields of two types (a
search field and a text field). A `{n}` or lead-in element whose label ticks between the read and the tap is
chosen again: the same element at its new label is acted on, and a different one never silently — the step
reads the screen until it settles once more, and refuses, naming both, if it still finds a different one.

### Typing

`type` resolves the label among elements that can actually take text, taps it, types, and reports
the step as landed only if the field's own value then changed to carry what was typed. `validate`
refuses a blank label on any step and a `type` step whose `text` is empty, which would tap the
field, type nothing, and report the step as having landed.

**`type` has not been seen to complete a walk on this toolchain** (SimWalk#3). Resolution and
focus work against a real simulator; `typeText` then fails with *"process main thread busy for
30.0s"* — against Settings as well as the app under validation, and the same stall hits a plain
`tap` on a search field, so it is the simulator's keyboard wedging the app rather than the step. The
cause is UIKit's synchronous pasteboard XPC, with no frame of the app under test in the stall; the
host-side mitigation is `defaults write com.apple.iphonesimulator PasteboardAutomaticSync -bool
false`. **The blast radius is fixed**: that screen is now one refused entry in the manifest, and the
rest of the walk's captures survive it.

## Tapping a point with `tapPoint`

`tapPoint` is for an accessibility tree that lies (SimWalk#29): Apple Health's charts keep the previous
period's bars in the tree at zero size after a period switch, and freeze their hero on a selected bar, so a
bar is reachable by where it is drawn and by nothing the tree says. **Reach for the form with a `label`
first**: `at` is then two fractions of that element's frame from 0 to 1 (`[0.8,0.5]` is four fifths across,
halfway down), which lands on the same part of the chart on any device; the label resolves the way a
`scrollTo`'s does. Without a `label`, `at` is a screen point in device points. `validate` refuses an `at`
that is not two numbers, a fraction outside 0…1, and a negative screen point — including a screen point
whose coordinates are both at most 1 written without a `label`, which is refused by name as the likelier
slip: a fraction meant to measure an element, with the `label` that would have made it one left off. A
`label` written as an explicit `null` is refused too, rather than silently read as absent. A screen point
beyond the device's far edges can only be refused when the walk runs, since `validate` is not told the
device — and it is, as is a point within an element whose frame is empty or lies off the screen: the step
is UNREACHABLE, naming why, never a touch somewhere near.

A `tapPoint` lands one quiet period after its touch, unconditionally. No read of the tree lands it
sooner: a ticking label, a spinner and a callout change the tree exactly as a real push does, so a push
that reaches the tree within the quiet period is on screen by the time the step lands, and a bar that only
lights up, or a callout that appears and dismisses, lands when the quiet period is up. Nothing after the
touch makes the step UNREACHABLE. A push slower than one quiet period is not waited for, so a later route step
after such a `tapPoint` can run against the old screen; the quiet period is the one of the screen the step is
taken on, as for a bar control above, so that screen's `settle` (or `--settle`) lengthens it. **State
`expect` on any screen whose route ends in a navigating `tapPoint`**: the step lands on the clock alone,
one quiet period after the touch, so landing says nothing about where it went — a push, a selection, a bar
that merely lights up and a slow push not yet on screen all land alike — and `expect` is the only check that
confirms the right screen was actually reached. The manifest's route records the step as `tapPoint`, so a reader can tell it was placed by coordinates rather than resolved by label — and
note the one thing no walkbook can check: a point that lands on something else drawn over the element (a
chart whose lower edge sits under a tab bar, say) taps whatever is on top, `expect` on the destination is
what would catch that too.

## Answering system sheets with `systemTap`

Use `systemTap` when a permission sheet or alert stands in the way of a route, such as the notifications alert or HealthKit's authorization sheet.

`systemTap` answers a system sheet (SimWalk#28): it looks for an enabled, hittable control by label or
identifier in SpringBoard's tree (where the notifications alert lives), then in the app's (where HealthKit's
authorization sheet is hosted), for up to 10 s. **In the app's tree it takes only a control in a subtree
the app's own screen did not have** before the sheet could be up — read after the launch and before
each step that is not a `systemTap` (so a sheet that step raises is new), kept while the sheet stays up
(HealthKit's first page to its second), and read again once a sheet has closed after a `systemTap`
(SimWalk#39), so a notifications primer the app shows then is its own. A control that was on the app's
screen before is never tapped as a sheet's, nor its list scrolled; the step is UNREACHABLE naming the
label instead, and names itself **ambiguous** where that screen already held a match: the app's own
control, or — for a route that begins with a `systemTap` — a sheet already up when the launch's screen was
read, and that refusal names the declaration below (SimWalk#39 item 2). Where no sheet showed at all, the
refusal ends that a sheet already answered is not asked again — unless the device booted under ten minutes
before (read from its `launchd_sim` as the runner starts): then it names the boot's age and says to wait and
walk again on the same device, since HealthKit raises no sheet on a freshly booted simulator for its first
minutes and erasing or rebooting it restarts that wait (SimWalk#88). On a fresh boot, for a step declared `atLaunch` (below), the refusal does not claim the app's window showed no sheet — its tree cannot tell — so it says SpringBoard showed none, gives the boot's age, and asks for the label to be checked as well (SimWalk#90). **An app whose launch raises the sheet** (HealthKit's, asked from its initialiser) has no screen
without it, so the route's first step declares that — `{"systemTap":{"label":"…","atLaunch":true}}`
(SimWalk#46) — and its control is then taken on the author's word rather than on being new: nothing of the
launch's screen counts as the app's. `validate` refuses the key on any later step, and the manifest's
`routeTaken` records it (`systemTap '…' at launch in the app's window`), so a reader knows on whose word the
control was taken. Two limits follow from the declaration being the author's word. On a launch screen that
is the app's own — the sheet late, or already answered — the step drags the app's list and may tap the
app's controls: a wrong declaration, not a runner fault, and the manifest's `at launch` is what says so. And
for a sheet hosted in the app's window (HealthKit's) the at-launch scope is never dropped: its only baseline
path is the root, so the sheet never reads as closed, the step that closes it waits out the dismissal wait,
and a later `systemTap` in the same route answers from the same accept-everything scope. On iOS 27 a remote
sheet's content (HealthKit's, hosted by `com.apple.HealthPrivacyService`) is in the app's snapshot only on
the first app launch after the host starts; on a relaunch the snapshot ends where the sheet is hosted.
**`systemTap`'s reads put it back** (SimWalk#48): where the tree has an on-screen childless anonymous
`Other` and the app has more live descendants than the tree has nodes, the runner walks the live hierarchy
(at most 40 live queries, 2–4 s: a count or an element's snapshot each, and the `exists` a count below the app and a known root's read ask first is charged against the same cap — SimWalk#57) to the sheet's root and grafts its own snapshot
there, and the rest of the step reads that one element: two live queries per tree read beside
`app.snapshot()` — its `exists`, then its `snapshot()` — and no child count. A known root is kept only while it still has a
place in the tree, and a walk that found no root is not made again while the tree keeps its shape — labels
and values aside — so a screen with no sheet pays it once per step, not on every poll (SimWalk#56), unless
the walk reached a host placeholder with zero live children: content can still arrive there, so that walk
is made again next read rather than remembered. A tree
counts as already holding the sheet only where it holds most of the sheet's labelled and identified controls,
so a sheet that fills the screen is grafted too (SimWalk#57); they are matched by label and identifier alone,
since a table still decelerating between the two reads moves its rows and turns some into `Button`s (SimWalk#58). **Only `systemTap` pays for it** — its baseline, polls and dismissal reads; a capture's tree is
the snapshot alone, so a screen captured under such a sheet on a relaunch does not show the sheet. A
disagreement the graft cannot close is still refused naming it, and the walk's verdict counts it apart
from a missing control (`1 screen unreachable behind a system sheet the app's snapshot cannot see`,
SimWalk#55); `xcrun simctl terminate <udid> com.apple.HealthPrivacyService` before the walk, or a
reboot, is the workaround.
**The known limit:** a control of the app's that the step before brings in is read as new and
admitted as `appWindow` — a `tap` that pushes the app's own page with an identified `Allow`. A primer the app
shows a beat after a sheet closes is narrowed, not gone: the first read after the close waits for the app's
screen to hold still for the step's quiet period (the `settle` of the screen it is taken on, else the walk's),
so a primer that arrives within it is the app's own; an app slower than that still gets its primer admitted. With no `settle` anywhere that period is one 250 ms interval, so a primer later than about a quarter of a second passes; give the screen a `settle` to widen it. The wait cuts both ways: a second sheet the app raises by itself within that period — a HealthKit request chained after the first — joins the baseline, and the `systemTap` that answers it is refused as ambiguous instead of admitted. Where the app has a control of the same type, label and identifier as a sheet
hosted in its window, the sheet's is refused too, because a remote sheet reports its frames in its own
coordinates. Read `"owner":"appWindow"` as "in the app's window, and not there before", not as proof of
whose it is. **A second limit follows from a node's path carrying no position among siblings** (SimWalk#42
item 2): where a page the app pushes in the sheet's place is, like the sheet, an unidentified container of
the same type under the same parent, it reads at the sheet's own path, so `hasClosed` reads the sheet as
still up even though every trace of it is gone. **A third limit is one round trip wide** (SimWalk#51):
each candidate is read from a snapshot, then live (`exists`, its frame, `isHittable`), then from a second snapshot,
and tapped only where the two snapshots are the same control (type, identifier, label, box); a live read that fails — the control gone after `exists`, or a cell under the sheet's header whose activation point XCUITest calls invalid — passes the candidate over, as an expected failure rather than one against the walk (SimWalk#60). What is left is a
matching set that reorders and reorders back between the two snapshots, leaving the live frame another element's;
and the tap, which follows the second snapshot by one round trip. The manifest's `routeTaken` records which tree each control came from
(`systemTap 'Allow' in SpringBoard`, `"owner":"springboard"` / `"appWindow"`, written by the runner and
refused in a walkbook). A scroll container that such a subtree brought, once it has been up for 2 s
without the control, is dragged towards its end, because a sheet's buttons below the fold are not in the
tree as buttons until they are on screen; the app's own list is never scrolled. **It answers a sheet in one state only**: each state is a fresh launch, and a permission answered in
the first state is not asked again, so the second state finds no sheet and its route is UNREACHABLE. Walk a
permission sheet with one state, on a device that has not answered it (`xcrun simctl erase`). A capture
taken while a SpringBoard alert covers the app — an element SpringBoard's tree types `Alert`, the only
kind the check recognises — is refused as `captureFailed` naming the alert, never filed with the app's tree
beneath it. `Fixtures/PermissionFixture/` holds a fixture app and both walkbooks.

## Commands

This is every verb with its main options. The sections after it explain each one.

```sh
simwalk validate <walkbook.json>   # parses and checks the walk can be executed as written
simwalk validate <walkbook.json> --device   # ... and that a physical device could walk it
simwalk walk <walkbook.json> --output <bundle.simwalk> --device <physical udid> --team <TEAM>   # on a phone
simwalk walk <walkbook.json> --output <bundle.simwalk>   # runs it against a simulator
simwalk walk <walkbook.json> --output <bundle.simwalk> --lease <token>   # on the device a lease holds
simwalk walk <walkbook.json> --output <report.json> --dry-run   # follows every route, captures nothing
simwalk bundle inspect <path>      # summarises a bundle: screens, outcomes, refusals, what is on disk
simwalk bundle screen <path> <step>   # one screen's identifier and the text on screen, by the number inspect lists
simwalk bundle audit <path>        # every rule (chevron rows, unlabelled controls, symbol-name labels, shared labels, targets under 44 pt, reading order, overflow at accessibility type); --only <rule>, repeatable, picks some; --walkbook <walkbook.json> adds the motionBudget and performanceBudget rules over the screens' `budgets`
simwalk lease acquire [--device <udid|name>] [--clone-from <udid>] [--physical <udid>] [--ttl 30m]   # a device of your own, and its token
simwalk lease list                 # what is leased, to which pid, until when — never the tokens
simwalk lease renew <token> [--ttl 30m]   # extend a lease; never shortens it
simwalk lease release <token>      # give it back; a clone is shut down and deleted
simwalk bundle oracle <path> --walkbook <walkbook.json>   # each figure the walkbook names, read off the bundle and checked against the walkbook's oracle command; exit 2 on anything but a match
simwalk bundle diff <ref> <run> [--crops <dir>]   # form differences between two bundles (presence, order, box), a crop PNG per flag; and, for walks with motion on, a layout shift present on one side only (matched by element type, identifier and label, never box or time; a flag line `shift only in run you/light: Button 'Row 2' moved 0,+72 pt — cause: ...`, no crop; a side with no shift record is a note, not a flag; settle time is never compared); exit 2 on any flag the reference does not also have, or anything not compared (a flag both bundles carry, `also in reference`, is printed and tallied apart and does not count: a bundle against itself exits 0)
simwalk usage                      # what has been called, how long it took, what failed and why, what it saved
simwalk usage --since 3d           # the same over the last three days (or 12h); --unredact prints failure reasons
simwalk mcp                        # the MCP stdio server (JSON-RPC on stdin/stdout)
simwalk statusline                 # this session's segment, fed the status-line JSON on stdin
simwalk install                    # set SimWalk up in each agent found (Claude Code, Cursor), asking once per agent
simwalk doctor                     # prove each agent simwalk install sets up is wired end to end
simwalk install-hook               # install the walk runner; with Claude Code, register the server, status line, PreToolUse hook and agent guide
```

More options, for the verbs that have many:

```sh
simwalk walk <walkbook.json> --output <dir.simwalk> [--screens <id>] [--dry-run] [--motion] [--animations] [--stock] [--device <udid|name>] [--app-path <x.app>] [--lease <token>] [--team <TEAM> --runner-bundle-id <id>  (physical device only)]
simwalk bundle audit <dir.simwalk> [--only <rule>]... [--walkbook <walkbook.json>]
simwalk bundle coverage <dir.simwalk>                  # controls no route step reaches, as the steps to add; exit 2
simwalk prune                                          # reclaims old runners and expired leases; install-hook runs it
simwalk uninstall-hook                                 # run before deleting the binary
```

Every verb writes the answer to stdout and a refusal to stderr, appends one line to
`~/.simwalk/usage.jsonl`, and exits **1** on a refusal. `usage` is the exception to the append alone,
and deliberately: it reads that log rather than writing to it, because a report that recorded itself
would make a machine whose usage is checked daily report checking as its most-used verb. Everything else
it owes a caller it still gives — a log holding lines this build cannot decode makes the report
**qualified** (exit 2, naming the count it is short by), and a log that is present and cannot be opened
is a **refusal** (exit 1) rather than a cheerful "no calls recorded yet" over a file full of them.

## Walking a walkbook

`simwalk walk` runs a walkbook against a device and writes a capture bundle. Run it with `--dry-run` first to check that the routes still resolve.

```sh
$ simwalk walk settings.walkbook.json --output run.simwalk
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 7977d45f  device: iPhone19,2 (27.0)  settled: 9/9
ok — 5 of 5 screens captured · 9 captures
  1 root — captured [light, dark, light-dt_uictcontentsizecategoryaccessibilityxl] via scrollTo 'General'
  2 general — captured [light, dark] via tap 'General'
  3 accessibility — captured [light] via tap 'Accessibility'
  4 display-text-size-lower — captured [light, dark] via tap 'Accessibility' → tap 'Display & Text Size' → scrollTo 'Smart Invert'
  5 apple-account-sheet — captured [light] via tap 'Apple Account'
settle: the accessibility tree had to hold still for 250ms before each capture — animations it cannot see (chart draw-in, cross-fades, image decode) are not covered

accessibility: the XCUITest session switched com.apple.Accessibility AccessibilityEnabled off as it ended, and this walk switched it back on for <udid> and saw it hold — in-process accessibility suites on this device build their trees as before
…
~64k tokens saved — 9 screenshots (~4.1k each at the 2576 px cap) and 114 kB of accessibility trees at 4 bytes a token, against 1.4 kB served. A floor: only what this answer stood in for is counted.
```

`--animations` keeps UIKit animations on in the app under walk (see "Animations"). `--screens <id>` walks only the screens you name, in walkbook order. The bundle records the subset as the plan it ran, so it does not stand in for a full walk. `--settle <ms>` sets how long a screen must hold still before each capture (250 ms by default, and a screen's own `settle` wins). `--motion` records motion on every screen.

**`--dry-run` checks that every screen's route still resolves, in seconds per screen, without
capturing anything** — the cheap check to run after app changes, before spending a full walk. It
follows each screen's route once against the booted app, launching every screen with its first
state's launch args, and writes a route-probe report to `--output` (a `.json` file, refused if it
already exists) in place of a capture bundle; it never checks a screen's `expect` and never touches
appearance. The dry run probes each screen under its first state's launch conditions only, and every
other locale, argument list or environment its states name is reported, not probed. `walk` exits **2**
when any route drifted, naming each step and its label; exit 0 means every route resolved.

```sh
$ simwalk walk settings.walkbook.json --output report.json --dry-run
walk: 'apple-settings'  app: com.apple.Preferences  build: 57388b49  walkbook: d21ef61b  runner: 7977d45f  device: iPhone19,2 (27.0)  dry run: routes only
ok — 5 of 5 routes resolved · nothing captured
  1 root — resolved: scrollTo 'General'
  2 general — resolved: tap 'General'
  3 accessibility — resolved: tap 'Accessibility'
  4 display-text-size-lower — resolved: tap 'Accessibility' → tap 'Display & Text Size' → scrollTo 'Smart Invert'
  5 apple-account-sheet — resolved: tap 'Apple Account'
each route followed once from a fresh launch, under its screen's first state's launch arguments and the device's own appearance; resolved means every step landed as a walk's would — the screen it reached is not checked against `expect`, which a walk does

accessibility: the XCUITest session switched com.apple.Accessibility AccessibilityEnabled off as it ended, and this walk switched it back on for <udid> and saw it hold — in-process accessibility suites on this device build their trees as before
```

### When Xcode's `simctl` is not ready

`walk` (a dry run too), `inspect` and `session start` check, once and before their first `simctl` call, that the Xcode on the machine can run `simctl` at all; a `--device` is looked up in `simctl list`, so a walk or a session start on a physical device named by `--device` is checked too, and one under a `--lease` on a phone, which makes no `simctl` call, is not. Some Xcodes ship a `simctl` that first runs `xcodebuild -runFirstLaunch` whenever the installed CoreSimulator is older than the version the script expects, and that command waits on an administrator password nobody is shown, so a call sat behind it forever. The check reads the version the script expects and the one installed, and refuses when the installed one is older or missing:

```
this Xcode's simctl expects CoreSimulator <expected> and <installed> is installed, so every simctl call first runs `xcodebuild -runFirstLaunch`, which waits on an administrator password — run `sudo xcodebuild -runFirstLaunch` (or open Xcode once), then retry
```

**No `simctl` call SimWalk makes is unbounded.** Each is stopped after a ceiling set by its verb: `boot` 120 s; `bootstatus`, `install` and `clone` 300 s; every other verb 60 s. A call that outlives its bound is stopped and refused naming it:

```
`xcrun simctl install <udid> <app>` did not finish within 300s and was stopped
```

Only when `xcodebuild -runFirstLaunch` was seen running inside the stalled call's own process tree does the refusal go on to name that cause and the fix ("it was waiting on `xcodebuild -runFirstLaunch`", then the same cause and fix as above). A stall with any other cause names the command and the bound and claims nothing more. An appearance read that is stopped this way is not a refusal: it leaves the device's appearance unknown, as any failed read does. The exception is the read a walk, a dry run, an `inspect` or a `session start` makes before its runner: stopped while waiting on `xcodebuild -runFirstLaunch`, it refuses the run with that cause and fix, since every `simctl` call after it would wait the same way.

## Devices and leases

Use a lease when more than one session walks at once, or when you want a device that is yours alone. A walk works on a simulator or on a physical iPhone or iPad.

### Leases

`simwalk lease acquire` takes an
exclusive lease on a device — the one named, a fresh clone of a shut-down device (`--clone-from <udid>`),
or an unleased device on the newest iOS runtime, a shut-down one first — and hands back its UDID and a
token; `walk --lease <token>` (and `inspect --lease`, and the MCP `walk`'s `lease`) walks it, and a leased
device is the walk's to reboot. A walk without the token never takes a leased device: with no `--device`
it passes over it, and naming it is refused before anything touches it. A lease is one file under
`~/.simwalk/leases`, created with `O_EXCL` so two callers cannot both hold one; it lasts its `--ttl`
(default 30m) or until the session that took it exits. Unnamed or by-name, `acquire` chooses only a
shut-down device (`noShutDownDevice` otherwise); a booted one is leased only when named by UDID. It warns
when the holder it found is its own parent and not a known long-lived process, and `--holder-pid` names the
right one. `lease list` shows what is held, never the tokens; `lease renew <token> [--ttl]` extends a lease
(never shortens it; refused once its holder has exited); `lease release <token>` gives it back, shutting
down and deleting a clone and nothing else; `prune` releases the leases that have expired (a lapsed clone
stays held until then), and removes stale temp files from the store. **Every walk holds a lease for its
whole run**: with `--lease` it renews that lease at the start and before its setup, appearance settle and
second pass; without one it takes an implicit lease (its own pid, 30 min) on the device it resolves and
releases it on every exit, so six walkers starting together take six devices. A walk that cannot renew makes
no setup, no reboot and no second pass, and the answer says so.

### Physical iPhones and iPads

**A physical iPhone or iPad is leased the same way** (SimWalk#116). `simwalk lease acquire --physical
<udid>` confirms with `devicectl list devices` (a read) that the UDID is a physical device, refusing otherwise
and naming the physical UDIDs present, then leases it; it is refused beside `--device` or `--clone-from`.
The lease records `physicalDevice: true`, `lease list` marks it `physical device`, and releasing it deletes
nothing. `simwalk device walk` takes `--udid` (an implicit lease: its own pid, 30 min, released on every
exit) or `--lease <token>` (renewed at the start, left to its holder; a token whose lease is not on a
physical device is refused), never both. The lease comes before any `devicectl` call, so a phone leased by
someone else is refused naming the holder with nothing run on it, and the walk renews again before the
runner starts. The device may stop the runner on a prompt for its passcode to allow UI automation; the refusal names the runner's own failure (read from its result bundle's summary) and says so, and the fix is to keep the device unlocked and enter the passcode when the prompt appears (SimWalk#124).

**`walk --device <physical udid>` is the device walk** (SimWalk#116). A `--device` that `simctl` lists no
simulator for (by UDID or name) is looked up with `devicectl list devices`, the read `lease acquire --physical`
makes; a physical one takes `device walk`'s path, unchanged in order: the lease, `device check`'s prerequisites,
the appearance read, the optional install, the device build, the runner, the container copy, the container
wipe and the handback. A `--lease` whose lease has `physicalDevice: true` takes it too, and the answer is
`device walk`'s. `--team` is required there and refused on a simulator walk, as is `--runner-bundle-id`;
`--app-path` is `device walk --app`'s install; `--screens`, `--settle` and `--motion` carry over (a subset is
executed as its own walkbook, hashed as itself); `--dry-run` is refused on a device. A `--device` known to
neither is refused as before, naming the physical UDIDs present when there are any. `validate --device` (MCP:
`device: true`) applies the device rules: whatever `DeviceTargetSupport` refuses is a problem, the same list
a device walk refuses with. `simwalk device walk` stays as an alias: it runs the same path, and its answer's
last line says `device walk is walk --device now`.

**A device walk keeps the runner installed and empties its container** (SimWalk#116). Once the bundle has
been copied back, or the copy has failed, on every exit after the runner ran, the walk empties the runner's
data container (`devicectl device copy to` an empty directory, `--remove-existing-content true`, which clears
the whole container in about 0.2 s). The answer (or the refusal) says `runner container emptied`; a wipe that
fails qualifies a good walk and never refuses it. It is pointed only at the runner's own container
(`<runner bundle id>.xctrunner`), never a walkbook's app. A refusal before the runner ran wipes nothing.
`simwalk device clean (--udid <udid> | --lease <token>) [--runner-bundle-id <id>]` uninstalls the runner app
(`devicectl device uninstall app`) under the phone's lease, as `device walk` takes it; it names what it
removed, and a runner that is not installed is an answer, not a refusal. `simwalk device check (<udid> | --udid
<udid>) --team <T>` checks a phone's walk prerequisites (team, pairing, connection, Developer Mode, lock) before any
build and answers `walkable` or refuses naming the one that failed; it takes the UDID positionally or as `--udid`,
as the other `device` verbs do, and refuses neither or both (SimWalk#129).

**`device walk --app <path.app>` installs the build it walks** (SimWalk#116). The `.app`'s
`CFBundleIdentifier` must be the walkbook's `appBundleID` and its executable is hashed
(`AppBuildIdentity.hash(ofAppAt:)`) on the Mac, both before the lease: a wrong or unreadable `.app` is refused
with nothing run. The install (`devicectl device install app`) comes after the prerequisites and before the
runner build, and a failed install refuses naming devicectl's error. The manifest records
`appBuildProvenance: installed` (optional, no format bump; absent means read back from the installed app, as
every simulator walk is), written by the runner from `SIMWALK_BUILD_PROVENANCE` beside the hash. The answer
prints `build: <hash> (installed by this walk, not read back)` and says the phone's previous copy of the app,
if any, was replaced and not restored. Without `--app` the build stays `device-unread`. `bundle diff` counts an
installed hash as a build: two bundles are the same build when their bundle ids and hashes match and neither
is `device-unread`, and the facts line says `build same (installed, not read back)` when either side was
installed.

## Reading a bundle

A bundle is the folder a walk writes. These verbs read one without a device.

A bundle path missing its `.simwalk` suffix is completed, never refused (SimWalk#107):
`walk` and `device walk` write `<output>.simwalk` when nothing exists at `--output` (the answer's header
ends `output: <path> (suffix added)`), and every `bundle` command reads `<path>.simwalk` when `<path>` is
absent and that exists (`(read <name>.simwalk: suffix added)`). A path that exists unnamed is still refused.

### `bundle inspect` and `bundle screen`

`simwalk bundle inspect <bundle>` summarises a bundle: screens, outcomes, refusals and what is on disk. `bundle screen <bundle> <step>` shows one screen's identifier and the text on it.

**`bundle screen <bundle> <step>`** (MCP: `inspect` with `step`). `step` is the 1-based position in
`bundle inspect`'s listing, or the screen's id. It gives the **screen identifier** (the first identifier
the app set on a container; never a bar's, an image's, a control's or a framework's; when a sheet, alert or
popover covers the screen, the presentation's) and **the text on screen** with value, type and frame, in
accessibility order. `--state <slug>` picks a state; with none, a multi-state screen answers for the first
and the verdict names the others (SimWalk#101). Off-screen elements are counted, not listed; `--all` lists
them after the on-screen ones, each marked `(off screen)`. `--match <text>` narrows the listing and searches
on screen and off, on-screen hits first. `--tree --match <q>` lists the nodes `q` names (a substring of label,
value or identifier, or a whole type) as `Type 'label' [id] x,y w×h [= 'value'] [selected] [disabled]` with an
`in:` ancestor chain (anonymous runs fold to `Other×7`); `--bars` lists every TabBar, Toolbar and NavigationBar,
alone or with `--tree --match` for the union; `--all` lists off-screen nodes (SimWalk#121). Use these, not a
script over `ax-tree.json`. Overlays with no presentation type
(toast, HUD, banner) are read with the screen. Text only: visual form needs the screenshot.

### `bundle audit`

`simwalk bundle audit <bundle>` checks accessibility and layout rules over every capture in a bundle.

`bundle audit` runs its seven default rules, one verdict over all of them, the coverage stated once, and a
`[rule]` heading per rule. **A rule that found nothing keeps its heading and its arithmetic**
(`[unlabelledControl] clean — 22 controls examined across 2 captures`), so a rule that ran clean is not
mistaken for one that was never asked for. `--only <rule>` (repeatable; the MCP tool's `only` array) runs
just the named rules: `disclosureAffordance`, `unlabelledControl`, `symbolNameLabel`, `duplicateLabel`, `smallTarget` (enabled control under 44×44 pt), `readingOrder` (tree order against the layout) and `largeTypeOverflow` (text past the screen or over a sibling, at accessibility Dynamic Type sizes only); an
unknown name is refused, listing these. Two more rules are opt-in. The first, `motionBudget`: `--walkbook <walkbook.json>` (the MCP tool's `walkbook`)
holds each screen's recorded `motion` to that screen's `budgets` (see the walkbook screen keys). Without a walkbook that states any, a default run's heading
reads `[motionBudget] not run — no walkbook budgets (pass --walkbook)` (or `(the walkbook states no budgets)` when one was passed) and it is not counted;
naming it in `--only` (the MCP `only`) with no budgets to check is refused as input refused, non-zero exit, naming why, so an `ok` never stands for a check that ran on nothing. A screen not captured, a capture with no motion record
and a `layoutShifts` budget over a record without `shifts` are UNREACHABLE (never "within budget"); a settle past the budget, a watch that never
settled, and more shifts than allowed are over budget; the last lists each shift's element and cause. A walkbook other than the one the bundle was walked
from qualifies the verdict.

The second, `performanceBudget`: with `--walkbook`, it holds each screen's `budgets` keys `launchMs`, `transitionHitches`, `cpuMs` and `memoryPeakMB` to the median of the figures a physical-device walk measured. A simulator bundle, or a capture with no performance record, is UNREACHABLE for it. Without such budgets a full run prints `[performanceBudget] not run — no walkbook performance budgets (pass --walkbook)`. A control seen in light, dark and a Dynamic Type state is one
finding naming its states.

### `bundle diff`

`simwalk bundle diff <ref> <run> [--crops <dir>]` compares two bundles by form and writes a crop for each flag.

**`diff` flags.** Open only the crops a flag names, not the screenshots. A flag marked
`list — may be data-driven` is a section of same-shaped rows: open its crop and treat it as a value.

### `bundle coverage`

`simwalk bundle coverage <bundle>` lists the controls no route step reaches, as the steps to add. It exits 2 when it finds any.

### The value oracle

Use the oracle to check that the figures an app shows are the figures a program you trust computes.

A walkbook names the oracle and the figures: a top-level `oracle: {"command": ["path", "arg", …]}` (`command[0]`
absolute runs as written, relative with a `/` resolves against the walkbook's directory, a bare name is looked up on
`PATH`; never a shell) and, per screen, `figures: [{"id": "steps-today", "element": "<identifier, label, or a label
pattern with one {n}>", "windows": ["midnight", "rolling24h"]}]`. Window names are free strings SimWalk never
interprets. `simwalk bundle oracle <bundle> --walkbook <walkbook.json>` (and the MCP `oracle` tool) reads each figure
off every captured state and asks the command, in **one process per check**, speaking JSON lines: one request per
line on stdin, keys sorted, `{"capturedAt":"2026-09-29T08:15:02.125Z","figure":"steps-today","locale":"en_US","screen":"today","state":"light","windows":["midnight","rolling24h"]}`;
one reply per line on stdout, in request order, `{"values": {"midnight": 3326, "rolling24h": 2703}, "unit": "count", "attribution": "…"}`
or `{"error": "…"}`. A timeout (30 s), a non-zero exit, truncated output or a wrong count of replies fails every
request. One line per figure per state: `matches <windows>`, `matches none`, `not on screen`, `no figure`,
`oracle failed`, `screen not captured (<outcome>)` for a figure on a screen the walk did not capture, or
`state not captured (<why>)` for one in a walkbook state a captured screen holds no capture of. Only a
match is clean; anything else exits 2, as does a walkbook whose hash differs from the bundle's (stated, and the
figures are matched by screen id). A bundle without capture times, or a walkbook with no `oracle`, is refused (exit 1).

## Live reads and sessions

Use `simwalk inspect --app <bundle id>` to read the screen a running app is on right now. It launches and captures nothing, and it refuses a device that is not booted. A session keeps a runner resident on a device so you can read and step through an app repeatedly.

```sh
$ simwalk inspect --app com.apple.Preferences
live: app: com.apple.Preferences  runner: 7977d45f  device: iPhone19,2 (27.0)
ok — live read of com.apple.Preferences — root 'com.apple.settings.sidebar.collectionView', 19 text elements on screen
screen 3698a96b
Settings · StaticText · 16,120 133×41
Apple Account, Sign in to access your iCloud data, the App Store, Apple services and more. · Button · 16,168 370×90
apple.id · Image · 32,183 60×60
Apple Account · StaticText · 100,183 138×24
Sign in to access your iCloud data, the App Store, Apple services and more. · StaticText · 100,210 236×34
General · Button · 16,293 370×52
Accessibility · Button · 16,345 370×52
Action Button · Button · 16,397 370×52
Appearance · Button · 16,449 370×52
Camera · Button · 16,501 370×52
Home Screen & App Library · Button · 16,553 370×52
Search · Button · 16,605 370×52
Siri · Button · 16,657 370×52
StandBy · Button · 16,709 370×52
Screen Time · Button · 16,796 370×52
Vertical scroll bar, 2 pages = 0% · Other · 369,116 30×696
Toolbar · Toolbar · 0,0 402×874
Search · SearchField · 28,808 346×28
Dictate · Button · 342,811 17×22

text only — colour, shape and visual emphasis (a capsule vs. a line) still need a screenshot (xcrun simctl io <udid> screenshot <file>.png)

accessibility: the XCUITest session switched com.apple.Accessibility AccessibilityEnabled off as it ended, and this walk switched it back on for <udid> and saw it hold — in-process accessibility suites on this device build their trees as before
~3.6k tokens saved — 1 screenshot (~4.1k at the 2576 px cap), against 1.7 kB served at 4 bytes a token. A floor: only what this answer stood in for is counted.
```

**Live sessions** (`simwalk session start|read|step|save|end|list`, and the MCP `session` tool) keep one runner resident on an owned device —
named by UDID or taken by lease — so reading the running app's screen costs about 0.4 s instead of a runner
launch per `inspect`. `start --app <bundle id> [--state <json>] [--animations]` launches the app under a capture state and
prints an id; `read <id> [--match <text>]` answers in `inspect`'s form; `end <id>` stops the runner, puts back
what it changed on the device (the appearance it was found in, accessibility) and removes the session;
`list` shows each session and whether its runner is still running, and switches the device's accessibility back
on, once, for a session whose runner stopped without `end` (the XCUITest teardown switched it off, and after an
idle exit nothing else on the host runs to put it back) — unless something else is using the device: a running
session, a `start` still holding its claim, anyone else holding its lease, or a walk, dry run or `inspect` holding
a walk claim (`<leases>/.walks/<udid>/`, taken under whatever lease it runs, so a walk under the session's own
`--lease` counts), any of which may be rebooting or reading it; the `list` after they are done makes the restore.
`end`, and a `start` whose runner never became ready, leave such a device alone the same way, each with a line
saying why (SimWalk#128). A device found with accessibility already back on
once the teardown's budget has passed since the session's `exit.json` is recorded as needing nothing, with no write,
no wait and no qualification. A runner that died without `exit.json` is bounded by its `heartbeat.json`, rewritten
every 2 s until the runner stops: its stop is taken as no later than three intervals after the last beat, and the
wait runs from there as it would from `exit.json`; only a session with neither file (a runner from before the
heartbeat, one that never reached serving, or one whose last beat could not be written) still gets the whole wait from now, qualified. `end` on a runner that had exited before it hands back
the same way: its wait runs from `exit.json`'s stop time or the heartbeat's bound, and a restore `list` already
recorded for that stop is reported as `list`'s, with no wait and no write (one recorded as failed or unconfirmed is
made again). `list` makes one restore per device, dated from the latest stop among the sessions it records it for,
and the record names that stop; `end` reuses it only when it is no earlier than every stopped session's on the device
(a session with no stop and no record counts as stopped now, and a record from before SimWalk#92 names none), and
otherwise restores dated from that latest stop, so one `end` waits out every stopped session's teardown still to come on the device. A runner `end` itself stops is waited on from the exit `end` saw, never from its `exit.json`, which is written before the teardown. A state whose theme the device is not in
reboots the device into it before the runner starts, which is the one cure measured for a simulator that
reports an appearance it does not draw. A session ends itself after 900 s without a request
(`SIMWALK_SESSION_IDLE_SECONDS` overrides it). Sessions are for exploring; a walk remains the reproducible
record. `step <id> '<route step JSON>' [--guard <hash>]` performs one step with the walk's own code and
answers the step as a walkbook writes it, then (for a `tap`, `scrollTo` or `type`) a `bound: label · Type · x,y w×h` line naming the element the label resolved to (SimWalk#93; ` = value` follows the label where the element has one — for a `type` step, the field's value or placeholder before typing), the new screen hash and what appeared and disappeared; a guard whose
hash is stale is refused before anything acts. `save <id> --screen <id> --into <walkbook.json>` writes the
steps that landed as a validated walkbook screen, to walk from then on; save before `end`, which deletes the
session.

## Usage report: `simwalk usage`

`simwalk usage` reports what has been called, how long it took, what failed and why, and what it saved. Use it to see whether the tool is working for you.

**`usage` breaks failures down by kind**, because a caller deliberately testing a refusal path getting
refused is not the same fact as the tool falling over: `input-refused` (a bad argument, a missing
walkbook), `route-unreachable` and `device-left-bad` (named, not yet produced by any site),
`runner-failed` (the walk runner's own machinery), `setup-failed` (`install-hook`/`uninstall-hook`
against Claude Code's own CLI or configuration), and `tool-error` (this tool's own code — the MCP server
and a command disagreeing about an argument vector, or a verb failing past its argument for a reason
nothing classified — never a caller's). **"Failed" and "refused" mean one thing each**, in the report
and on the status line alike: refused is `input-refused`, failed is everything else that did not
succeed. The headline counts failures, leaves refusals out and says how many — and its verdict word
follows what it found: `ok` only when there is nothing to flag, `qualified` (exit 2) once there is a
failure or a line it could not decode. A line written before the field existed is classified from its
own error text where that text is unambiguous, marked as inferred, and otherwise `unclassified` — kept
apart from `unrecognized-kind`, a `kind` this build's own decoder does not know (from a newer `simwalk`,
decoded leniently rather than tearing the line).

**Each kind names its reasons**, most-recorded first, so a stewardship pass can tell whether a known bug
is still costing walks. They are **pseudonymised by default** — a reason quotes whatever the call was
pointed at, and a report is built to be pasted — as `reason-3f2a1b`, salted per machine so one reason
keeps one token from report to report; `--unredact` prints the text, in the same row order. `--since 3d`
(or `12h`) narrows the whole report to a rolling window, and the header names it beside how many calls
the log holds overall.

**`SIMWALK_USAGE_LOG` moves the log** to the file it names, and the state kept beside the log — the
status line's scan cache, the redaction salt — moves with it. Anything that drives the binary and is not
a real use of it (a test, a review, a mutation run) sets it, so the report stays a record of real use.
`HOME` moves the directory the log lives in, so it does not do that job.

**`HOME` and `SIMWALK_HOME` move everything else.** Every path built from the user's home (`~/.simwalk`,
`~/.claude`, `~/.local/bin/simwalk`) follows `HOME` when it is absolute. `SIMWALK_HOME` moves `~/.simwalk`
alone, and `SIFT_HOME` moves the `~/.sift` the status-line shim goes under, as it moves sift's own. A relative
or empty value is ignored. A harness sets `HOME` to a scratch directory to run `install-hook` and
`uninstall-hook` entirely inside it. `CFFIXED_USER_HOME` beats `HOME` when both are absolute. **Coordination
state never follows these:** device leases (`~/.simwalk/leases`), live sessions and the Mirroring lock stay
under the account's own home for every process, so a scratch-`HOME` session still sees the user's leases;
only per-user state (usage log, runner, config, hook files) follows the overrides.

## Notes for writing walkbooks

These notes are for whoever writes or edits a walkbook, a person or an agent.

The installed agent guide (`SimWalk.md`, as `~/.claude/rules/simwalk.md`) carries only what an agent needs
to use the tools safely; the detail it points here for is below, beside what this reference already says
about route steps, states, `setup`, `expect` and the oracle.

- **Where walkbooks live.** A repo may keep its walkbooks in a folder of its own (some use `Docs/Walkbooks/`, with a README). If yours does, read that README before writing a new one.
- **A dark capture brighter than mid-grey is refused as a light render** even when the screen is bright by
  design (web view, PDF, photo): leave that screen's `dark` state out of the walkbook, or read the refusal as
  expected.
- **The appearance settle.** A device whose appearance was just changed can draw light under a `dark`
  state. What the simulator does not keep across a boot is gone (a `simctl status_bar override` does not
  survive it). Only an appearance refusal triggers it, at most once a walk.
- **Where an `expect` identifier lives.** It must be a content identifier (typically on the scroll view or
  container).
- **Hand-driving the simulator.** A context hears the nudge at most once per 30 minutes and never on its
  first such call (SimWalk#110): that call, and its identical re-run, go through; the next distinct call is
  refused once. The refusal of `simctl io … screenshot`, `simctl ui … appearance` or
  `axe tap` in a repo with walkbooks lets the command it names through on a second run, alone or beside
  anything but another simulator command — the allowance is keyed on that command's own words, not on the
  rest of the call. `simwalk inspect --device <udid|name> --app <bundle id> [--match <text>]` reads the
  running app for a fraction of a screenshot's tokens.
- **Sessions.** A step that does not land is qualified and `save` names it. `save` also takes
  `[--expect <identifier>]` and `[--since <n>]`. A screen with a changing value (a clock) changes its hash
  every read; step it unguarded.

## Driving a real iPhone with `simwalk mirror`

Use `mirror` when you want to look at, or tap on, a real iPhone from your Mac through macOS's iPhone Mirroring window.

`simwalk mirror …` drives a real iPhone through macOS's iPhone Mirroring window with guarded mouse and wheel
events, and observes it as Vision OCR text (SimWalk#113). It never types. Every
verb re-activates Mirroring and refuses unless it is frontmost, before and after its events.

| verb | does |
| --- | --- |
| `mirror read` | reads the screen; no event |
| `mirror tap <fx> <fy>` | taps at fractions (0…1) of the window's width and height |
| `mirror swipe <fx1> <fy1> <fx2> <fy2> [--ms 350]` | drags for `--ms` 50…5000 (anything else is refused); moves the home screen and App Switcher, **does not scroll inside an app** |
| `mirror scroll <lines> [--horizontal] [--at <fx>,<fy>]` | wheel lines at a place (default `.5,.5`); positive reveals what is below, or to the right; 1…50 lines either way, 0 and beyond are refused. A negative count goes after `--` |
| `mirror menu home\|switcher` | clicks View > Home Screen / App Switcher. From the App Switcher `home` lands in the last app first: send it twice (the `switcher` answer says so) |
| `mirror burst <fx> <fy> --frames <n> [--sheet]` | taps, then 1…60 frames as fast as capture goes; `--sheet` writes `sheet.png` (six tiles to a row, labelled `f03 +412ms`) beside the frames |

`read`, `tap`, `swipe`, `scroll` and `menu` also take `--match <text>` (only the lines containing it are
listed as served), `--settle-ms <n>` (default 3000: the longest to wait for the screen to stop changing) and
`--out <dir>`. `burst` takes `--out` alone.

**The answer** is OCR text lines with their boxes (centre x,y, width, height, as the fractions the next tap
takes), `+` lines new since the action and `gone:` what went, and the screenshot's path. When no text
changed the answer is qualified (exit 2), not a success: the tap may have landed on something that did not
react. A burst answers one line per frame, with what each added and lost against the one before, and
`frames <dir>` (and `sheet <path>`) naming where the files are.

**Exit codes**: 0 answered; 1 refused (a fraction outside 0…1, no Mirroring window, a missing grant, a menu
item not found); 2 qualified; **3 not frontmost** — the one refusal whose right response is to retry, so it
has a code of its own (and `not-frontmost` as its usage-log kind).

**Where captures go**: the standard store (`~/.simwalk/mirror/captures`, newest hundred kept) unless `--out <dir>`
names a directory, which is never pruned. Captures and burst directories are named in UTC, `<yyyyMMddTHHmmss-SSSZ>-<label>`, so a prune by name order is a prune by time across a clock change; the answer's clock time stays local. A refused argument (frames, `--settle-ms`, `ms`, `lines`, `--at`, the menu item) logs as `input-refused`. The MCP tool `mirror` takes the same verbs as one `action`
(`read, tap, swipe, scroll, menu, burst`) with `at` and `to` as `[x, y]` fractions, `ms`, `lines`,
`horizontal`, `item`, `frames`, `sheet`, `match`, `settleMs` and `out`; an argument the action does not take
is refused by name.

## Using SimWalk from a coding agent (MCP)

`simwalk mcp` is the same tool over JSON-RPC 2.0 on stdin/stdout, for a coding agent rather than a
person. Eight tools (nine for a bounded client, below) — `walk`, `validate`, `inspect`, `audit`, `diff`, `session`, `oracle`, `mirror` — each answering **word for word what the
matching CLI verb prints**, because the MCP server has no options of its own: it translates a tool call
into the subcommand's own command line and lets the subcommand parse it. An option added to `walk` is
therefore an option both have (the one exception is `walk_status`, below, which has no CLI verb), and a refusal the command makes of its own arguments (`--settle 0`
would be silently discarded, so it is refused) reads the same over either.

A refusal comes back as a tool result marked `isError`, reading `refused — <reason>` — not as a
JSON-RPC error, because the call was well formed and the model is meant to read the reason. A
**qualified** answer is not marked as an error at all; its verdict line says so. A line that is not a
request is told apart three ways, because they send a client somewhere different: `-32700` for bytes
that are not JSON, `-32600` for JSON that is not a request (a bare array, an object with no `method`),
`-32601` for a method not served. Stdout carries JSON-RPC and nothing else: a walk takes minutes and
none of it reaches that stream until the answer does, and a client that closes the pipe ends the
session from the failed write rather than leaving the server parked on a read.

**An argument that is present and unusable is refused, never dropped.** A `settle` of `0.5`, of
`"900"` or of `true`, a `screenIDs` that is not a list of ids, a blank `device` — each is a caller
asking for something, and walking at the default over it is the silent-discard failure the tool exists
not to have. The quiet period is passed as `--settle=<n>` so that a negative one reaches the command's
own refusal (`--settle takes a quiet period in milliseconds greater than zero`) rather than the
parser's complaint about a missing value.

`walk`'s `dryRun` boolean maps to `--dry-run` the same way; a non-boolean is refused like any other
mistyped argument. A dry run never counts as a walk on the status line — it is counted, and priced,
as a call, whether it arrived as `dryRun: true` here or as `simwalk walk --dry-run` from a shell.

A walk over MCP or the CLI writes its progress to `~/.simwalk/progress/<session>.json` while it runs (the
session is `CLAUDE_CODE_SESSION_ID`, `default` without one; the directory is the usage log's, so
`SIMWALK_USAGE_LOG` moves it), and ends by writing a compact `<session>.result.json` — capped at 16 KiB —
named on the answer's last residue line, `result: <path>`; an answer with no result file is unchanged.
`verbose` (`--verbose`) lifts the cap and adds each step's states and route taken; it is refused beside
`dryRun`, which writes progress but no result. The schemas are in `Docs/SIMWALK-PROGRESS.md`.

### Bounded walks

A walk takes minutes, and some clients cut a tool call off long before that (Cursor, at 60 s). A server
therefore answers a `walk` in one of two modes, chosen from the client's name.

- **Blocking.** The server records `params.clientInfo.name` from `initialize`. A client named `claude-code`
  gets what `walk` has always done: one call, answered when the walk ends. For it `tools/list` is
  byte-identical to today's and `walk_status` is not listed. Renaming that client would switch it into
  bounded mode, which is why a test pins the bytes.
- **Bounded.** Every other client, including one that sends no `clientInfo`, gets the rest of this section.
  `SIMWALK_MCP_CLIENT`, when set, replaces the recorded name (for tests).
  A bounded client's `initialize` result also carries a short `instructions` string (about 1 KB: dry run first, the
  verdict lines, `walk_status` handles, `inspect` with `step`), because Cursor's model reads it. Claude Code's result has no
  `instructions` key and so costs nothing idle; it has the full guide as a rule file.

`SIMWALK_MCP_CALL_BUDGET` is the longest a bounded call waits, in seconds; fractions are accepted. The
default is 50, under a 60 s cut-off with margin. A value that is unparsable or not positive falls back to 50,
with one line on stderr when the server starts. Waits suspend on an injected clock rather than block, so tests
do not sleep.

**The handle.** `<stem>@<pid>-<startedAtMs>`: the progress-file stem (`<session>` or `<session>.<slot>`), the
walk's `pid`, and the file's `startedAt` in epoch milliseconds (both are schema v1 keys). The stem alone is
re-claimed by the next walk on the machine, so a handle carries the two keys that tell walks apart. A handle
is accepted only if it matches `^[A-Za-z0-9_-]+(\.[0-9]+)?@[0-9]+-[0-9]+$`; it is used as a file name, so
anything else is refused (row 1) before the filesystem is touched.

**`walk` (bounded).** The walk starts off the server's actor and the call waits up to the budget; `dryRun`
walks are treated the same way.

- The walk ended within the budget (re-checked at expiry, so a walk that ended just then is returned):
  exactly the text the blocking call returns, with the same `isError`.
- Otherwise the `running` line (grammar below), `isError: false`.

**`walk_status`** (bounded mode only). Input `{ "handle": string }`, required. The server keeps one
in-process state per walk it started, `running` then `ended(answer)`, behind one lock. For such a handle
`walk_status` consults that state and never the file's phase: ended returns the held answer, verbatim and
byte-for-byte on every poll; running waits up to the budget from the start of this call, then returns the
`running` line. A held answer is kept per full handle for the server's lifetime; a poll whose response a
cancel suppressed consumes nothing. For any other handle the file is read, by this precedence, first match
wins:

| # | Case (handle this server did not run) | Answer | `isError` |
| --- | --- | --- | --- |
| 1 | handle does not match the regex | `refused — <value> is not a walk handle` | true |
| 2 | no progress file | `refused — no walk <handle>` | true |
| 3 | unreadable, or not schema 1 | `refused — the progress file for <handle> is unreadable` / `… is schema <n>, and this server reads 1` | true |
| 4 | file `pid` or `startedAt` differs from the handle | `refused — the walk <handle> was replaced by a later run under <stem>` | true |
| 5 | `tool` is `session` | `refused — <handle> is a live session, not a walk` | true |
| 6 | phase not final, process gone | `refused — the walk <handle> ended without finishing: the process running it exited` | true |
| 7 | phase not final, process alive | wait up to the budget, reading the file once a second; each read re-applies rows 2–11 and the first row other than 7 that matches answers at once; at the budget, the `running` line | false |
| 8 | final, `resultPath` set (even with `error` set) | the ended answer | by verdict |
| 9 | final, no `resultPath`, `error` set | `refused — the walk <handle> ended: <error>` | true |
| 10 | final, no `resultPath`, no `error`, `tool` is `walk --dry-run` | `ok — the dry run <handle> finished; a dry run keeps no result file` | false |
| 11 | final, no `resultPath`, no `error`, any other `tool` | `refused — the walk <handle> ended but its result file was not written` | true |

Rows 1–6 and 8–11 answer at once; only row 7 waits. "Process gone" is the reader rule in
`Docs/SIMWALK-PROGRESS.md` (the dead-process rule there). Apart from held answers, `walk_status` reads files only, so a poll
works from any server process, and after a crash it answers instead of hanging.

**Answer shapes.** `isError` is true only for a refusal, everywhere in this section: a `qualified` answer and
the `running` line are `false`.

```
refusal  := refused — <reason>                            (AnswerVerdict.refused; isError true)
running  := running — <handle>: <phase>[, step <i>/<n>[ <screen>]][, <failed> failed, <passed> of <planned> passed]; call walk_status with this handle
ended    := <header: walk name, app, device, from result.json>
            ok — … | qualified — … | refused — …          (verdict passed | failed | refused)
            result: <path>
dryrun   := ok — the dry run <handle> finished; a dry run keeps no result file
```

The ended answer's verdict line carries the result's `counts` as `<failed> failed, <passed> of <planned>
matched`; a `refused` verdict carries the first failure's reason instead.

`running` is the one documented exception to the verdict-word rule: a status line with nothing measured.
Its pieces come from the progress file, for this server's own walk too; a final phase there (the file goes
final before the walk returns, and at once on a cancel) is printed as `finishing`. The step piece appears only
when `currentStep.index` is at least 1 and `total` is non-null, `<screen>` only when non-null, and the counts
piece only when `matches.planned` is above 0, failures first. A client tells the shapes apart by line 1: if it
begins `running —`, `refused —` or `ok — the dry run`, that line is the whole answer; otherwise line 1 is the
header and the verdict is on line 2. Only `running` means poll again.

**One device-touching walk at a time.** While a bounded walk runs (judged from the in-process state, never
the file), `walk`, `session` and `mirror` are refused with `refused — a walk is running (<handle>); poll it with walk_status, then retry` (`isError: true`).
The refusal names the handle, so a client whose `walk` call was cancelled before it answered can still poll.
Every other tool, `walk_status` included, is answered, because the actor is free.

**Concurrency (for the implementer).** In bounded mode the read loop hands each `tools/call` to its own task;
for `claude-code`, calls are still answered one at a time, in arrival order, exactly as today. The walk runs on
a dedicated `Thread`, not the cooperative pool, calling the existing synchronous answering path. The actor awaits a continuation and stays free. Waits
suspend on the injected clock. `InFlightRequest` becomes a map keyed by request id, so overlapping calls each
keep their own cancellation. The answering path reports the claimed stem, `pid` and `startedAt` through a
callback. The claim and the progress file's `begin` happen before target and device resolution, so the
callback fires within milliseconds of the call and the handle always exists before the budget runs out; the
builder moves them earlier if they do not.

**Cancel.** `notifications/cancelled` for a `walk` call that has already answered with a handle changes
nothing. Before that, the answer is suppressed and the walk ends its progress file `failed` with
`error: "cancelled"` (`ProgressWriter.cancel`) and runs on; the in-process state is unaffected, so the walk is
polled by the handle the busy refusal names. A bounded walk nobody polls runs to its end. There is no
`walk_cancel`: a deliberate limit.

**Server exit (for the implementer).** On stdin EOF the server stops reading and exits only after the walk
thread has returned, as the blocking path does today. No signal handling is added: SIGTERM, like SIGKILL, ends
the process mid-walk, as today, leaving a stale progress file that the dead-process rule answers. A runner
child (`xcodebuild`) can outlive a killed server, as it can today.

**Usage log.** A bounded walk logs its one usage line when it ends, with its true duration, saving and
failure kind, not when the first call returns. Each poll logs as `walk_status`: a `SimWalkTool` case and a
`defaultFailureKind` arm. `walk_status` has no CLI verb, the one exception to "each tool answers what the
matching CLI verb prints"; a bounded client lists nine tools, the eight above and `walk_status`. For
`claude-code`, a call to `walk_status` is refused as an unknown tool, and that refusal lists the eight; the test
pinning the catalog's size against `SimWalkTool.allCases` becomes per-client. `README.md` and `SimWalkTool`'s
doc comment, which say eight, are updated with the code.

**Tool catalog.** `MCPToolCatalog` becomes per-client. For `claude-code` the `tools/list` bytes are identical
to today's. The bounded `walk` description is today's with "A walk takes minutes and nothing is served until
it finishes; the answer names" replaced by "A walk takes minutes, and a call answers within the budget with
either the answer or a handle to poll with walk_status; the answer names". `walk_status`'s description: "Poll
a walk that 'walk' answered with a handle: waits up to the budget, then returns the walk's answer if it has
ended, else one running line with its progress." Its schema: `handle` (string, required), described as "the
handle that 'walk' returned on its running line"

**Acceptance (tests).**

- With an injected clock and a fake walk lasting 2.5 budgets: call 1 returns the `running` line, poll 1
  returns progress, poll 2 returns the answer; with the budget cut-off set aside, call 1 blocks to the end.
- Handle reuse: a later run under the same stem, then a poll of the old handle: the replaced refusal.
- A second poll returns the same held answer.
- A cancel before the handle, then the busy refusal naming it, then a poll that works.
- Another server's ended walk: its header, verdict word and `isError`.
- The ended-before-returned race: the file final, the in-process answer not yet returned, then a poll gets the held answer,
  never the file's.
- A dry run; a session handle; a malformed handle.
- `claude-code`: one call returns the answer, `walk_status` is absent, and `tools/list` bytes equal the
  recorded fixture, with the real Claude Code 2.1.302 `initialize` line as a fixture.
- A server killed mid-walk, then a poll from a new server: the `exited` refusal, not a hang.
- A second `walk` during a bounded walk: the busy refusal.
- EOF mid-walk: the process exits only after the walk ends.
- A `validate` sent while a bounded `walk` call is waiting is answered before the budget runs out.
- `claude-code`: a second call sent during a walk is answered after the walk's answer.
- A walk that ends without a result file, and is not a dry run: row 11.

## Installing with `simwalk install`

`simwalk install` finds Claude Code, Cursor and Codex on this machine and sets SimWalk up in each one chosen, then prints one summary. It is safe to re-run; a second run changes nothing and says so.

```sh
simwalk install --yes                           # every agent found, without asking
simwalk install --agent cursor --cursor-dir DIR # Cursor only, into DIR instead of ~/.cursor
```

- `--agent claude|cursor|codex` (repeatable) installs into that agent whether or not it was found; `--all` names all three; `--yes` takes every agent found. With none of them it asks once per agent on a terminal, and installs nothing without one.
- `--cursor-dir` is the directory holding Cursor's `mcp.json` and `hooks.json` (default `~/.cursor`). `--guide` is passed to the Claude Code step as `install-hook --guide` takes it.
- Claude Code's step is `install-hook`'s own answer (runner snapshot, server, status line, `PreToolUse` hook, guide). Cursor's step registers `simwalk mcp` and the `preToolUse` hook `simwalk hook pre-tool-use --agent cursor`, leaving other tools' entries alone; Cursor support is experimental, and it has no status line or machine-wide rule.
- Codex is not supported yet: `codex: not supported by simwalk yet — skipped`, never a failure.
- Exit 1 when any agent's step failed; the others still run. `install-hook` and `uninstall-hook` stay, for Claude Code alone.
- After its own step and summary, `simwalk install` runs the other Fieldwork tools' installs once (`sift install --agent <a>… --yes`, for the agents SimWalk ran a step for, Codex included) from `PATH` or beside the `simwalk` binary, printing `family: running sift install --agent <a>… --yes` before each; a member that is not found prints nothing, one that fails adds `family: <member> install exited <status>`, one that cannot be started adds `family: <member> install could not be started: <reason>`, both make the exit 1, and nothing runs where `FIELDWORK_FAMILY_INSTALL` is set (a member started by the step has it set, so it never loops). The step runs whenever any agent was picked, Codex included (SimWalk skips Codex, but `sift install --agent codex` still runs), even when SimWalk's own step failed; nothing runs when no agent was picked.
- `--dry-run` writes nothing and runs no `claude`: it names, per agent, what the step would do, then passes `--dry-run` to the other tools' installs. For Claude Code it follows the step's own decisions: the runner snapshot and prune always; then, where `claude` is on PATH, the `PreToolUse` hook in `settings.json`, the status line (in sift's segment file where sift is installed, in `settings.json` otherwise), the guide and `claude mcp add`, each worded "would install or update" since nothing is compared with what is there; where `claude` is not on PATH, one line saying those four would be skipped. Cursor's lines name `mcp.json` and `hooks.json`.

## Checking an install with `simwalk doctor`

`simwalk doctor` proves each agent `simwalk install` would set up is wired end to end, for Claude Code and Cursor. One line per check, led by a verdict line:

```sh
simwalk doctor                                   # every agent found on this machine
simwalk doctor --agent cursor --cursor-dir DIR   # Cursor only, from DIR instead of ~/.cursor
simwalk doctor --json                            # the same answer as one JSON object
```

- Per agent it checks the registration (the hooks, the MCP server, for Claude Code the rule), then that the registered binary runs and reports this version, then each registered hook fed a payload of that agent's shape, then that the registered server starts and lists SimWalk's tools. Everything it runs runs in a scratch home, removed before it answers, so the checks never write to your usage log.
- With no `--agent`, an agent not found is named and skipped, and an agent found with nothing of SimWalk's in it is named and not counted. `--agent claude|cursor` (repeatable) checks that agent whether or not it was found; `--cursor-dir` names Cursor's directory and checks Cursor. Codex is not checked, since SimWalk does not support it, and `--agent codex` is a usage error.
- Exit 1 when any check failed, or when agents were found and none has SimWalk installed.

## Installing with `simwalk install-hook`

`simwalk install-hook` sets SimWalk up on this machine. Run it from the repo root. It is safe to re-run, and re-running is how you upgrade the registrations. A new binary gets its runner at its own first install.

```sh
simwalk install-hook     # from the repo root
```

A binary installed by Homebrew, npm or a release tarball has no checkout, and `install-hook` then takes the runner
from the tree shipped beside it: `<prefix>/share/simwalk/` for `<prefix>/bin/simwalk`, found with symlinks in
the binary's path resolved (Homebrew links `bin/simwalk` into its Cellar). The tree is used only when its
`BINARY_SHA256` stamp equals this binary's SHA-256, and its `RUNNER_COMMIT` names the snapshot. Its
`RUNNER_FILES` stamp lists every other file as `shasum -a 256` prints it; the snapshot holds exactly those files,
each checked against its hash as it is copied, so a file an older package left behind, a `.DS_Store`, a missing
file or a changed byte never reaches a runner: the install refuses, naming the file and both hashes. A tree
stamped for another binary, or with a missing or malformed stamp, is refused, and the `runner: not installed`
line names every place it looked and why each was unusable. The shipped tree is tried first, the checkout the
binary was compiled from second. **A walk installs the shipped tree by itself**: the first walk after
`brew upgrade` or `npm update` finds a new binary with no pairing, installs the tree shipped with it and walks
that, without re-running `install-hook`. A walk never snapshots a checkout.

It always installs **the walk runner**, copied out of the checkout this binary was compiled from into
`~/.simwalk/runner/snapshots/<commit>` and paired with the binary's SHA-256 **once**. A re-run
from a checkout that has moved since (another branch, uncommitted edits) keeps the runner the binary
was installed with and says so on the verdict, and `--repoint-runner` is the explicit way to replace
it. A walk builds that copy and nothing else, in `~/.simwalk/runner-builds/<commit>-<path hash>` —
so edits in progress in the checkout never reach an installed walk, and a binary is only ever paired
with the runner from the tree it was installed beside (SimWalk#16). "Clean" is judged strictly:
untracked files count whatever `status.showUntrackedFiles` says, and so do files marked
skip-worktree or assume-unchanged, so a snapshot named for a commit holds that commit. A binary
copied into place without an install refuses to walk, before it boots anything, rather than
borrowing another commit's runner. `SIMWALK_RUNNER_PROJECT` still names a runner explicitly, and a
development build (`swift run`, `.build/debug/simwalk`) builds the checkout it lives in — each in a
build directory keyed by its path alone (`runner-builds/tree-<path hash>`), so moving the tree
between commits is an incremental build, not a new one.

With Claude Code (`claude` on your PATH) it also makes four registrations:

- **the MCP server**, at user scope. The install first reads `~/.claude.json` (`CLAUDE_CONFIG_DIR` is
  respected) and decides: a registration that is already current is left alone; a stale one is removed and
  added again (`claude mcp add` fails outright on a name already present, and without the removal an
  upgrade leaves the *old* binary registered while reporting success); a server of another kind holding
  the name `simwalk` is refused rather than overwritten. It registers with
  `claude mcp add --transport stdio --scope user simwalk -- <path> mcp`, then reads the file back to
  confirm the registration is there.
- **the status line** (see [The status line](#the-status-line)).
- **the `PreToolUse` hook**, written into `~/.claude/settings.json`. It runs `simwalk hook pre-tool-use` before each shell call an agent makes. It tags a command-line `simwalk` call with its session, so the status line counts it. In a repo with walkbooks it also refuses some of an agent's own simulator driving, namely `xcrun simctl io … screenshot`, `simctl ui … appearance` and `axe tap`, and points at the SimWalk tool instead. The refusal comes once per 30 minutes, and the same command run again goes through (see Hand-driving the simulator in [Notes for writing walkbooks](#notes-for-writing-walkbooks)). Other tools' hooks in the same list stay as they were. `simwalk hook pre-tool-use --agent cursor` is the same hook for Cursor: it reads Cursor's `preToolUse` payload (its `Shell` tool as `Bash`), judges it the same way, and writes a refusal in Cursor's response schema; a call it lets through prints nothing. Without `--agent`, or with `--agent claude`, it answers Claude Code as before.
- **the agent guide**, `SimWalk.md`, copied to `~/.claude/rules/simwalk.md`, where its `paths:`
  frontmatter keeps it out of sessions that never touch a walkbook, a capture bundle or a UI-test
  target. It is looked for beside the binary, then in the `share/simwalk` tree a packaged release ships beside it, then in the working directory, which is why a checkout install is run from the repo root — a
  named `--guide` that cannot be read is reported rather than quietly replaced by another candidate.
  A `~/.claude/rules/simwalk.md` that is a *symlink* into a checkout is left alone in both directions;
  a file already identical to the guide is left; a file that differs is kept as `simwalk.md.bak-simwalk`
  before it is replaced, so somebody's own notes at that path are not lost (there is no stamp marker).

Without Claude Code it installs the runner, skips the four registrations and answers qualified (exit 2), saying so. To use SimWalk from another MCP client, have that client run `simwalk mcp`.

`--settings`, `--guide` and `--rule` move the destinations, which is what makes the whole install
checkable against a scratch directory rather than only against the machine it is run on. The file
writes happen **before** the call out to `claude`, so a refusal from the last step is never half-done
unannounced: it names every step already taken. That includes a `claude` that is on PATH but cannot
launch, which `install-hook` refuses (exit as a setup failure) with those steps listed. `simwalk
uninstall-hook` removes all four Claude Code registrations and nothing else: the runner's snapshots
and builds stay under `~/.simwalk` beside the usage log, and a status line somebody else configured and
a segment file this tool did not write are reported and left. It removes the rule file and its
`simwalk.md.bak-simwalk` backup (a symlink at either path is left alone). For the server it reads
`~/.claude.json` first: with nothing registered it answers `mcp: nothing registered` without calling
`claude`; otherwise it runs `claude mcp remove simwalk --scope user` and then `claude mcp remove simwalk`. Both verbs answer in the usual shape: the verdict is the exit code, and a step that could not be taken (a
status-line slot somebody else filled, a guide that was not found) is a named qualification rather
than a silent skip.

## The status line

`simwalk statusline` reads Claude Code's status-line JSON on stdin and prints one line for the session
it names:

```
simwalk ~22k tokens saved · 3 walks · 1 failed · 1 refused
```

The saving leads because it is the only figure that means anything on its own — a walk stands in for
screenshots somebody would otherwise have had to look at, and the call count says only that the tool
was used. Any zero part is omitted, and a session that never called prints **nothing at all**.

Two sources, deliberately kept apart. The **count** comes from the session's own transcript and its
subagents', so a walk driven from a shell is counted like one driven over MCP — a session that used the
command line must not read as one that never used the tool. A shell line counts when it **invokes** the
binary: the name in command position with one of the CLI's own verbs after it. Naming the file is not
calling it, and `ls -l ~/.local/bin/simwalk` is a deploy check rather than a walk. A call the user
**denied** is not one the session made: it is counted where the `tool_use` appears and taken back when
its result says it never ran. The test is whether the tool *answered* — any of the three verdict words
opens a line, and all three mean it ran, `qualified` (exit 2) very much included, since Claude Code
marks any non-zero exit as an error. What carries no verdict at all is the call that never happened.
The **saving, the failures and the refusals** come from `~/.simwalk/usage.jsonl`, keyed on
`CLAUDE_CODE_SESSION_ID`, which the MCP server records and the CLI does not: the log is shared by every
session on the machine, so a time window over it would hand one session another's saving whenever two
ran at once. The consequence is stated rather than hidden — **a shell call is counted and never
priced**, and the line claims nothing for it. For the same reason the count reads `walks` only when
every counted call was one; otherwise it reads `calls`. **"Failed" and "refused" mean exactly what
`simwalk usage` means by them** — failed is the tool not answering, refused is a caller's own argument
turned away — so a session whose every walk fell over never reads as a clean one, and a runner failure
never reads as the caller's mistake.

Claude Code has a single `statusLine` slot and sift already owns it, so where `~/.sift/` exists this
installs an executable shim at `~/.sift/statusline.d/simwalk` and sift appends its line. Where sift is
absent the slot is taken directly — but only when it is free or already ours; a status line somebody
built themselves is reported and left alone. `simwalk statusline --hide` silences the segment without
touching the registration (so an upgrade cannot resurrect it); `--show` reverses that.

Scanning is incremental — one state file per session under `~/.simwalk/statusline/` (beside the log,
wherever `SIMWALK_USAGE_LOG` puts it), so each render reads only what has been appended to the
transcript and the log since the last one.

## Building

```sh
sh setup.sh     # first time on a fresh checkout: tools, linter, git hooks
swift build
swift test
```
