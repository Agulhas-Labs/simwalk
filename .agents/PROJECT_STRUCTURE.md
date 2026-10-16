# Project structure — SimWalk

```
SimWalk/
├── README.md                            the front page
├── LICENSE
├── CLAUDE.md / AGENTS.md / .agents/     agent guidance (this layer)
├── SimWalk.md                           the agent guide, installed as ~/.claude/rules/simwalk.md
├── Docs/
│   ├── Reference.md                     every verb and walkbook key in full
│   └── SIMWALK-PROGRESS.md              the progress file and compact result a walk writes
├── Package.swift                        SPM package: Core + Driver + MCP + CLI + tests
├── Sources/
│   ├── SimWalkCore/                     walkbook model, capture bundle, differ, oracle protocol
│   │   └── Extensions/<Framework>/      extension-only files, named after the type they extend
│   ├── SimWalkDriver/                   orchestration: simctl + xcodebuild, host-only by nature
│   ├── SimWalkMCP/                      the agent-facing face: MCP stdio server (stdout carries
│   │                                    JSON-RPC only), status-line segment, Claude Code registrations
│   └── SimWalkCLI/                      `simwalk` executable — thin ArgumentParser face
├── Tests/
│   ├── SimWalkCoreTests/                core Swift Testing suites (+ Fixtures/ resources)
│   ├── SimWalkDriverTests/              child-process reading and simctl's JSON, both other people's formats
│   ├── SimWalkMCPTests/                 the wire protocol, the segment's wording, the registration writes
│   ├── SimWalkCLITests/                 the CLI face's own contract: stream, exit code, log line
│   └── SimWalkTestSupport/              helpers the test targets share — a target, not a suite
├── Runner/                              the generic XCUITest executor
│   ├── SimWalkRunner.xcodeproj/         committed, not generated, but not XcodeGen-free: it lists files
│   │                                    rather than syncing a folder, so a new runner source file is
│   │                                    simply not compiled until `xcodegen generate` runs here
│   ├── project.yml                      what the project *is*, for humans; the .xcodeproj wins
│   └── SimWalkRunner/                   UI-test target, Target Application deliberately unset
├── Fixtures/                            apps and walkbooks real walks run against
│   ├── PermissionFixture/, RouteFixture/ XcodeGen fixture apps, each with its walkbooks
│   ├── SegmenterFixture/                XcodeGen fixture app and walkbook for the scroll segmenter
│   └── Settings/                        walkbook for Apple's Settings (no app of ours): regenerates
│                                        the local `Captures/settings.simwalk` calibration bundle
├── githooks/                            pre-commit (format + lint staged files) and pre-push (tests + runner build on main); `sh setup.sh` activates them
├── .swiftlint.yml, .swiftformat         lint and format configuration
└── setup.sh                             fresh-checkout bootstrap (tools, hooks, then an optional setup.local.sh)
```

Layout rules: one top-level type per file; an extension-only file is named after the type it extends
and lives under `Extensions/<Framework>/`; the pure core never imports SwiftUI; per-app XCUITest
runner targets live with the app under validation, not here. Capture bundles
written by local runs land in `Captures/` (gitignored) — outputs, never sources.

`SimWalkTestSupport` is a plain target under `Tests/` rather than a test target: a file belongs to
exactly one target, so the only way two suites can share a helper is for it to have a target of its
own. It is not a package product, so nothing outside this package sees it.

`SimWalkMCP` is named for the face it started as and holds everything that is *about an agent using this
tool*: the JSON-RPC server, the status-line segment that reports on it, and the writes into Claude Code's
configuration. They belong together rather than in the core because none of them is part of the walk
contract a work monorepo would consume, and they belong out of the CLI because the CLI is meant to stay a
thin face — the server owns the protocol and the log line, and is *handed* the verbs (`MCPToolRunner`),
which is what keeps the driver's `Process` dependency out of this module and the whole surface testable
without a simulator.

The mirror faces (SimWalk#113): `Mirror*Command.swift` in `SimWalkCLI` (a parent and one thin command per
verb; `MirrorStepOptions` holds the options the five step verbs share and the one place a step becomes an
answer), over `MirrorStepping` and `MirrorContactSheet` in `SimWalkDriver` (the protocol a test fakes in
place of the runner; the `--sheet` image). The MCP tool is one more case in `MCPToolInvocation` and
`MCPToolRunner`, and exit 3 for a lost focus is made in `TimedCall`, the one place an exit status is.

`SimWalkDriver` is split from `SimWalkCore` by *platform*, not by taste: it spawns processes and `Process`
does not exist on iOS, while the core has to build for the simulator because the bundle's write side runs
there. A target boundary makes that a fact about dependencies rather than a `#if` scattered through files,
and keeps `SimWalkCore` the pure contract layer the portability rule requires.

`Runner/` is the one part of this repo that is not SwiftPM, because **SwiftPM cannot build a UI-test
target** — the runner app is stamped from `XCTRunner.app` in the platform SDK by Xcode's build system.
It links `SimWalkCore` as a local package dependency, which is why the package declares `.iOS` as well
as `.macOS`: the capture bundle's *write* side executes on the simulator, so the core has to build for
both sides of the runner boundary or the runner would need its own copy of the writer. `Runner/` is in
the lint paths — it is the write side, so it is the most important place for the maintainers' derived-path lint
to apply, not the least.

The runner's sources: `WalkRunner.swift` (the one `XCTestCase` — a walk, a dry run and a live read in
`testWalk`, the states and the filing, and `testSession`), `LiveSessionServer.swift` (a live session's
resident server, which `testSession` hands over to: the launch, the read and handing the device back,
around the core's `LiveSessionLoop`), `StepPerformer.swift` (the one executor of a route step, made per step by
`WalkRunner.follow`, so anything else that takes a step takes it with the code a walk uses),
`TargetResolution.swift` (a step's label resolved and bound to the live element, over the core's `ScrollSearch` seek),
`BarClearance.swift` (nudging a reached element out from under the bars) and `TabLocator.swift` (finding a `tab` step's tab),
all split out of `StepPerformer`,
`AXTreeCapture.swift` (a snapshot turned into an `AXNode` tree) and `HostReachabilityProbe.swift` (that
the runner can write host paths). A new one is added to `SimWalkRunner.xcodeproj` by hand or by
`xcodegen generate`.

`walk --dry-run` (SimWalk#1) adds `Sources/SimWalkCore/RouteProbe.swift`, `RouteProbeError.swift`,
`RouteProbeReport.swift` and `RouteProbeSummary.swift` (the report the runner writes in place of a
capture bundle, and the answer built from it), `Sources/SimWalkCLI/WalkDryRun.swift` (the CLI face's
dry-run path, beside `WalkCommand`), and `Tests/SimWalkTestSupport/RouteProbeFixture.swift` (a report
the CLI and MCP tests share) — same split as a walk's own bundle and `CaptureBundleFixture`.

The progress file and compact result (`Docs/SIMWALK-PROGRESS.md`) add, on the host's side,
`Sources/SimWalkCLI/WalkTelemetry.swift` (the phases and segment timings a walk and a dry run write, handed to
`WalkCommand.performWalk` / `WalkDryRun.perform`; `nil` writes nothing) and its
`Tests/SimWalkCLITests/WalkProgressWiringTests.swift`.

`simwalk inspect` (SimWalk#49, a live read of the app on the device) adds `Sources/SimWalkCore/LiveScreen.swift`
(what the runner writes: the app's state, one tree, its identity), `LiveScreenError.swift`, and
`LiveScreenQuery.swift` (the answer, listed by `BundleScreenQuery`'s own text code so `--match` behaves as
`bundle screen`'s does), `Sources/SimWalkCLI/InspectCommand.swift` (the verb, beside `WalkCommand`) and its
`Tests/SimWalkCLITests/InspectCommandTests.swift`, and `Tests/SimWalkDriverTests/RunnerInvocationTests.swift`
(the environment `RunnerInvocation.inspect` hands the runner). The runner's side is a third mode of
`WalkRunner.testWalk` (`SIMWALK_INSPECT=1`), not a new file — the Xcode project lists its files explicitly.

The live session's runner side adds `Sources/SimWalkCore/LiveSessionLoop.swift` (launch, ready, requests
served in order until `end`, the idle timeout or a failure, and an exit record on every way out), tested by
`Tests/SimWalkCoreTests/LiveSessionLoopTests.swift`, beside the channel's own `LiveSession*.swift` files —
among them `LiveSessionHeartbeat.swift` (`heartbeat.json`, beaten from before the launch until `exit.json`, the
bound `list` waits from for a runner that died without one; its timer's ticks are scripted in tests by
`ScriptedHeartbeatSchedule.swift`);
the runner's half is `Runner/SimWalkRunner/LiveSessionServer.swift`, run by `WalkRunner.testSession`.
The host's half is in `Sources/SimWalkDriver/`: `LiveSessionStore.swift` (the directories under
`~/.simwalk/sessions`), `LiveSessionRecord.swift` (`session.json`), `LiveSessionStart.swift` (spawn and wait
for ready), `LiveSessionStop.swift` (end, signal only a group-leading `xcodebuild`, hand back, remove),
`LiveSessionAccessibilityHandback.swift` (`list` switching accessibility back on after a runner stopped without `end`),
`LiveSessionProcesses.swift` with `LiveSessionSystemProcesses.swift` (spawning in its own process group,
liveness, signals) and `LiveSessionHostError.swift`, plus `RunnerCommand.swift` (a command line and its
environment, which `RunnerInvocation.session` builds); the verbs are `Sources/SimWalkCLI/SessionCommand.swift`
with `Session{Start,Read,Step,Save,End,List}Command.swift`. Stepping and saving live in the core: `ScreenHash.swift`,
`ScreenDelta.swift`, `LiveSessionStepper.swift` (the guard and the step, decided where `swift test` sees them),
`LiveSessionStepAnswer.swift`, `LiveSessionStepQuery.swift`, `LiveSessionSave.swift` and `LiveSessionSaveError.swift`,
with `ExclusiveFileLock.swift` (the `flock` a save's load-modify-write and a start's claim both run under);
the MCP `session` tool reaches the same answers through `MCPToolRunner.sessionAnswer`. Tests:
`Tests/SimWalkCoreTests/{LiveSessionStep,LiveSessionSave}Tests.swift`, `Tests/SimWalkCLITests/SessionCommandTests.swift`,
`Tests/SimWalkDriverTests/{LiveSessionStop,LiveSessionSystemProcesses,LiveSessionAccessibilityHandback,RunnerSessionCommand}Tests.swift`, over
`Tests/SimWalkTestSupport/FakeSessionProcesses.swift` (a runner process a test states).

`bundle coverage` (SimWalk#35) adds `Sources/SimWalkCore/ControlCoverage.swift` (the controls a bundle's
trees expose that no route step covers) and `ControlCoverageSummary.swift` (its answer), and
`Sources/SimWalkCLI/BundleCoverageCommand.swift`, tested by `Tests/SimWalkCoreTests/ControlCoverageTests.swift`
and `Tests/SimWalkCLITests/BundleCoverageCommandTests.swift` — the same split as `bundle audit`.

`bundle audit` runs several rules (SimWalk#57 follow-up). `Sources/SimWalkCore/BundleAudit.swift` reads a
bundle once through `BundleAuditScope.swift` (which skips `unexpectedScreen` screens and states the
`Coverage`) and hands the trees to each rule; `BundleAuditSummary.swift` prints one verdict, the coverage
once (`AuditCoverageStatement.swift`) and a section per rule (`LabelAuditSection.swift`,
`AuditRowFormat.swift`). `AuditRuleName.swift` is the rule names both faces select by. The per-tree
rules conform to `LabelAuditRule.swift` — `UnlabelledControlAudit`, `SymbolNameLabelAudit`,
`DuplicateLabelAudit`, and the geometry rules `SmallTargetAudit`, `ReadingOrderAudit`,
`LargeTypeOverflowAudit` (shared frame questions on `AXNode.Frame`) — and return a `LabelRuleResult` of `LabelFinding`s over `AuditedControl`s; the
disclosure rule stays in `DisclosureAffordanceAudit.swift` / `DisclosureAuditSummary.swift`. Tests:
`Tests/SimWalkCoreTests/{BundleAudit,UnlabelledControlAudit,SymbolNameLabelAudit,DuplicateLabelAudit,SmallTargetAudit,ReadingOrderAudit,LargeTypeOverflowAudit}Tests.swift`, the
CLI's in `BundleAuditCommandTests.swift`, `--only` on the MCP path in `MCPToolInvocationTests.swift`, and
`Tests/SimWalkTestSupport/LabelTreeFixture.swift` (small trees of controls placed one under another).

Device leases add, in `Sources/SimWalkDriver/`,
`DeviceLease.swift` (one lease: token, holder pid, expiry, whether it created its device),
`LeaseStore.swift` (the files under `~/.simwalk/leases`: an `O_EXCL` create, every removal under a `flock`
on `.lock`), `DeviceLeasing.swift` (acquire, clone, release, `releaseExpired` for `prune`),
`HolderProcess.swift` (the pid a lease lives as long as) and `LeaseError.swift`; and in
`Sources/SimWalkCLI/`, `LeaseCommand.swift` with `LeaseAcquireCommand.swift`, `LeaseReleaseCommand.swift`
and `LeaseListCommand.swift`. `Simulator.resolve` is where a walk passes over or refuses a leased device.
Tests: `Tests/SimWalkDriverTests/{LeaseStore,DeviceLeasing}Tests.swift`, the resolve case in
`SimulatorTests.swift`, and the walk's refusals in `Tests/SimWalkCLITests/WalkCommandTests.swift`.

The walk-level setup block: `WalkbookSetup.swift` and
`PrivacyServiceName.swift` (the model and `simctl`'s privacy services) and `CaptureManifestSetupRecord.swift`
(the manifest's `deviceSetup`, and the only wording of its lines) in `Sources/SimWalkCore/`;
`DeviceSetup.swift` (the `simctl` vectors that make the setup and hand it back), `DeviceSetupJournal.swift`
(the per-device record under `~/.simwalk/setup` a killed walk leaves, and the next setup reads back) and
`DeviceSetupError.swift` in `Sources/SimWalkDriver/`. Tests: `WalkbookSetupTests.swift`, `DeviceSetupTests.swift`, and the walk,
dry-run and inspect cases in `Tests/SimWalkCLITests/`.

An **installed** `simwalk` never builds this directory: `install-hook` snapshots the checkout into
`~/.simwalk/runner/snapshots/<commit>` and pairs it with the binary, and walks build that copy into
`~/.simwalk/runner-builds/<commit>-<path hash>` (SimWalk#16). Only a development build under this
checkout's `.build/`, or `SIMWALK_RUNNER_PROJECT`, builds a working tree directly, into
`runner-builds/tree-<path hash>`. `RunnerBuilds` (in `SimWalkDriver`) names those directories and writes
each one's `simwalk-build.json` record of the project it builds; `RunnerPrune` reads the store and those
records to reclaim what nothing will walk again (`simwalk prune`, and every `install-hook`; SimWalk#22).

A runner that fails without a bundle is refused with what its result bundle says (SimWalk#50):
`Sources/SimWalkCore/RunnerActivityDigest.swift` reads `xcresulttool`'s activities JSON down to the ten steps before the failure, the failure and its triage's attachments (fixture `Tests/SimWalkCoreTests/Fixtures/runner-failure-activities.json`);
`Sources/SimWalkDriver/RunnerFailureDiagnosis.swift` makes the `xcresulttool` calls and exports the hierarchy beside the bundle.

`systemTap` asks the core whether a control read twice around its live reads is one control (SimWalk#51):
`Sources/SimWalkCore/SystemControlReread.swift`, tested by `Tests/SimWalkCoreTests/SystemControlRereadTests.swift`.

`systemTap` asks the core whether to drag a sheet's list again, from one read of the step's label (SimWalk#59):
`Sources/SimWalkCore/SystemTapScroll.swift`, tested by `Tests/SimWalkCoreTests/SystemTapScrollTests.swift`.

`scrollTo` asks the core whether to swipe again, and why it stopped, while its label resolves to nothing and then until its element takes a tap (SimWalk#74):
`Sources/SimWalkCore/ScrollSearch.swift`, tested by `Tests/SimWalkCoreTests/ScrollSearchTests.swift`.

`systemTap` reads the app's tree with a remote sheet's content put back where `app.snapshot()` stops (SimWalk#48):
`Sources/SimWalkCore/RemoteContentGraft.swift` decides each live read, tested by `Tests/SimWalkCoreTests/RemoteContentGraftTests.swift`.

The structural differ's segmenter: `Sources/SimWalkCore/Segmenter.swift` (the plug-in point),
`AXSegmenter.swift` (the tree-only rule), `ScreenSection.swift` and `TextShape.swift` (numbers → `{n}`), tested by
`Tests/SimWalkCoreTests/AXSegmenterTests.swift` on the trimmed trees `Fixtures/segmenter-*.json`.
The differ's pairing and form rules: `BundleDiff.swift` (screens by id, states by slug, unpaired and refused named, both
builds carried), `ScreenDiff.swift`, `StateDiff.swift`, `SegmentedCapture.swift` (a capture's sections and crops),
`FormRule.swift` with `PresenceRule.swift`, `OrderRule.swift`, `BoxRule.swift`, `RowTemplateRule.swift`,
`OverlapRule.swift` and `DegenerateChartRule.swift` (the last two rows' shared line-cutting is `TextRunLines.swift`),
`FormFlag.swift`, `SectionCrop.swift`, and `BundleDiffRendering.swift`; tested by `FormRuleTests.swift`,
`RowTemplateRuleTests.swift`, `OverlapRuleTests.swift`, `DegenerateChartRuleTests.swift` and `BundleDiffTests.swift`.
Its two faces: `BundleDiffSummary.swift` (the answer: verdict, header, saving), `BundleDiffCrops.swift` (writes the
crop PNGs with ImageIO, `<screen>__<state>__<n>.png`) and `BundleDiffError.swift` in the core; `BundleDiffCommand.swift`
(`simwalk bundle diff`, one `answer()` shared with the MCP `diff` tool through `MCPToolRunner`); tested by
`Tests/SimWalkCLITests/BundleDiffCommandTests.swift` and `diff` in `MCPToolInvocationTests.swift`.

The value oracle's core: the walkbook's `oracle` and a
screen's `figures` are `Walkbook.Oracle` and `Walkbook.Figure` in `Walkbook.swift`; `StateCapture.capturedAt` is
stamped by `CaptureBundleWriter`. In `Sources/SimWalkCore/`: `FigureScraper.swift` (find the element, read its number
under the locale), `FigureReading.swift`, `OnScreenFigure.swift`, the protocol `ValueOracle.swift` with
`OracleRequest.swift` and `OracleAnswer.swift`, `OracleCheck.swift` / `OracleCheckError.swift` (bundle × walkbook ×
oracle → one `FigureCheck` per figure per state) and `FigureCheck.swift` (the result model and its one-line
rendering). `Sources/SimWalkDriver/CommandOracle.swift` runs the walkbook's command through `Shell` (which takes stdin
`input` and a `workingDirectory` for it). Tested by `Tests/SimWalkCoreTests/{FigureScraper,OracleCheck,WalkbookFigure}Tests.swift`
and `Tests/SimWalkDriverTests/CommandOracleTests.swift` against the script `Tests/SimWalkDriverTests/Fixtures/fixed-oracle.sh`;
`Tests/SimWalkTestSupport/FigureFixture.swift` holds a sample screen, bundle and walkbook the suites use.

Its two faces: `OracleSummary.swift` in the core (the answer: verdict, one line per figure per state, a line for each
figure on a screen not captured, the walkbook-hash qualification, the saving) and `BundleOracleCommand.swift` in the
CLI (`simwalk bundle oracle`, one `answer()` shared with the MCP `oracle` tool through `MCPToolRunner`); tested by
`Tests/SimWalkCLITests/BundleOracleCommandTests.swift` and `oracle` in `MCPToolInvocationTests.swift`.

The progress file and compact result (`Docs/SIMWALK-PROGRESS.md`) are pure core, buildable for iOS so the runner
can write them: `Sources/SimWalkCore/WalkProgress.swift` (the live file's model), `PhaseTimings.swift` (the
boot/install/build/run split the progress `summary` and the result `timings` share) and `ProgressLocation.swift`
(`<usage-log dir>/progress/<session>.json` and `.result.json`), tested by
`Tests/SimWalkCoreTests/{WalkProgressCoding,ProgressLocation}Tests.swift`.
`ProgressWriter.swift` writes it (throttled `update`, always-written `commit`, the runner's `adopting`, the host's
`reload`) through `AtomicFileWrite.swift` (temp file beside the target, then `rename(2)`), and `ProgressRun.swift`
ends an abandoned run as `failed`/`interrupted`; tested by `Tests/SimWalkCoreTests/ProgressWriter{,Atomicity}Tests.swift`.
`Cancellation.swift` is a run's one-shot cancel (SimWalk#83), raised by `Sources/SimWalkMCP/InFlightRequest.swift` (a client's `notifications/cancelled` for the call in flight, heard by `FileHandleLines` as it is read) and `Sources/SimWalkCLI/TerminationSignals.swift` (SIGTERM/SIGINT to `simwalk walk`); tested by `Tests/SimWalkMCPTests/InFlightRequestTests.swift` and `Tests/SimWalkCLITests/WalkCancellationTests.swift`.
`WalkResult.swift` is the result file's model (§4) and `WalkResultBuilder.swift` builds it from a manifest — verdict,
counts and step outcomes from one `WalkProgress.Matches` fold, absolute screenshot paths through
`CaptureBundleLayout`, passed then failed steps dropped from the end over the 16 KiB cap, then failure text clipped, unless `verbose`; tested by
`Tests/SimWalkCoreTests/WalkResult{Builder,Coding}Tests.swift` (one fixture per outcome, the cap, the §4 golden).
`ProgressWriter.finish(writing:to:as:error:)` ends a run with its result, the result file written before the
terminal state that names it; tested by `Tests/SimWalkCoreTests/ProgressWriterResultTests.swift`.

The mirror target's OCR read path (SimWalk#113). Pure, Foundation-only, in `Sources/SimWalkCore/`: `MirrorTextLine.swift` (one recognised line, its box as top-left window fractions, and its confidence), `MirrorRead.swift` (one capture's lines in reading order — rows top to bottom, left to right within a row — with its path, `PNGSize` and the `capturedAt` the caller passes in), `MirrorRead+Comparison.swift` (`agrees(with:)` and `change(from:)` as added/gone multisets, both ignoring the status band `statusBandFraction` and judging positions to `positionTolerance`), and `MirrorSettle.swift` (the replayable answer-when decision: two agreeing reads that differ from the read before the event, qualified `noVisibleChange` / `stillChanging` at the bound). `Sources/SimWalkDriver/VisionTextReader.swift` is the Vision half (`.accurate`, no language correction, bottom-left boxes flipped to top-left fractions). Tested by `Tests/SimWalkCoreTests/Mirror{Read,Settle}Tests.swift` (scripted lines via `MirrorReadFixture.swift`) and `Tests/SimWalkDriverTests/VisionTextReaderTests.swift` over the synthetic `Fixtures/mirror-ocr.png`.

The iPhone Mirroring target's guarded device control (SimWalk#113):
in `Sources/SimWalkCore/`, `MirrorFraction.swift` (a coordinate as fractions of the window, refused outside `0…1`),
`MirrorWindowFrame.swift` (the window's id and frame, the pure fraction-to-point mapping, and the measured shape of the phone's screen inside it that refuses the transparent border and corners), `MirrorWindowStack.swift` (the window server's on-screen list as plain records, and the pure hit test that mints the `Pass` every event is posted on), `MirrorFocus.swift` (the
focus guard's decision over polled frontmost names, the single-read recheck, and the `Clearance` only a passing decision
mints), `MirrorFocusRefusal.swift` (lost focus, before the action / point covered / during a gesture / before a frame: exit 3, apart
from every other refusal) and `MirrorMenuItem.swift` (the two View menu items, never a free string); in
`Sources/SimWalkDriver/`, `MirrorWindow.swift` (the window server lookup and the hit test's snapshot), `MirrorFocusGuard.swift` (activate, then poll
System Events in-process), `MirrorEvent.swift` with `MirrorPoster.swift` (mouse and wheel only, each gesture taking a
`Clearance` and re-checked after its last event), `MirrorMenu.swift`, `MirrorCapture.swift` (`screencapture -l <id>`),
`MirrorCallLock.swift` (one call at a time per Mac, `~/.simwalk/mirror/.lock`) and `MirrorControlError.swift`. Tests:
`Tests/SimWalkCoreTests/{MirrorFocus,MirrorFraction,MirrorMenuItem,MirrorWindowStack}Tests.swift` and
`Tests/SimWalkDriverTests/MirrorControlTests.swift`, over scripted seams that post nothing.

The mirror target's step orchestration and answer (SimWalk#113): in `Sources/SimWalkCore/`, `MirrorAction.swift` (tap, swipe,
scroll or menu, with the short label the header carries), `MirrorObservation.swift` and `MirrorBurst.swift` (what a step
and a burst saw, as plain values) and their renderings `MirrorObservationSummary.swift` / `MirrorBurstSummary.swift` into an
`Answer` (header names OCR as the method, zero lines is qualified), over `MirrorSummaryText.swift` and
`MirrorFractionText.swift` (shared spellings); in `Sources/SimWalkDriver/`, `MirrorCaptureStore.swift` (kept captures
named by time and label, pruned to the newest 100, only ever its own names; an `--out` store never prunes) and
`MirrorStepRunner.swift` (one call's whole sequence under the call lock: guard, then window, before-read, event, settle
reads; or a burst, OCR only after the last capture; every Mac-touching dependency injected). Tests:
`Tests/SimWalkCoreTests/Mirror{Observation,Burst}SummaryTests.swift` and
`Tests/SimWalkDriverTests/Mirror{StepRunner,CaptureStore,ControlRefusal}Tests.swift` (with `MirrorStepScript.swift`, the
scripted seams).
