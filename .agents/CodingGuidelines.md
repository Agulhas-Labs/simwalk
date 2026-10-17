# Coding guidelines — SimWalk

Project-specific conventions on top of the general Swift style this repo follows (one top-level type per file, nested
types in extensions, caseless namespaces as `struct`, no implicit `.init`, Swift Testing with a blank
line before the first assertion, no `print()` — the CLI writes through its explicit
`StandardStreams`).

## Every answer takes the shared contract's shape

The form an answer takes is not this repo's to invent. **The sift repository's `Docs/AnswerContract.md`
is the specification** — one document, in one place, because a contract copied into two repositories is
two contracts within a month — and every face here builds an ``Answer``: a header naming what the answer
was measured against, an ``AnswerVerdict``, the residue, and what it stood in for.

- **The verdict word and the exit code are one value.** `AnswerVerdict` owns both and `TimedCall` is the
  only place either becomes a process's exit status. A command that computes its own qualification beside
  a summary that states one is two statements of a single judgement kept in step by hand — which is how
  `bundle inspect` came to print a bundle's shortfall and exit 0 over it.
- **Nothing empty is printed as a heading**, and the numbers that can go down come before the counters
  that only rise. A tally spelling out `0 capture-failed, 0 state-not-applied` on every clean walk is
  four words of noise and one habit away from a heading over nothing.
- **No dates and no machine names as *provenance*.** A hash is the only provenance; a bundle is read a
  week later on another machine as the normal case, so the run's timestamps and the device UDID stay in
  the manifest, which is the record. The exception, and the test for it: a date that is the answer's
  **subject** rather than its provenance stays — `usage`'s `days: 2026-08-16 → 2026-09-05` is *which
  window this is a report of*, which no other field can say, and is not the day the report was produced.
- **A saving is measured, stated as a floor, and carries the constants it was made with.** Screenshots
  by their pixels (``ImageTokenEstimate``), trees by their bytes (``TokenEstimate``), against the answer's
  own byte count — and an artefact that cannot be read is left out rather than guessed at. An answer that
  stood in for nothing carries no such line: a saving of zero is a measurement where the truth is an
  absence.

## The honest contract is a type, not a habit
- An unreachable screen is `ScreenOutcome.unreachable(routeTried:)` — never an empty capture, never a
  silently skipped entry. A build mismatch is a refusal that names both hashes.
- Answers state their own arithmetic: a diff says what it segmented and what it could not; an oracle
  answer names the window rule that matched. Do not add an answer shape that can't explain itself.

## An outcome names what was verified, not what was attempted
`captured` meant "the route ran without throwing" and was read by every consumer as "the target screen
was observed". Those are different claims, and the gap is where a bundle came to hold the Workouts
list under `rowing-detail` with the manifest saying it was reached. The rule that closes it, and the
one to apply to anything new: **before writing a claim, ask what evidence would have to exist for it
to be false, and check that instead of checking that nothing threw.**

- A step expected to navigate is landed only once `ScreenIdentity` says the hierarchy has *left* the
  screen it was taken on. Structure only — `isSelected`, `value` and geometry are excluded, because a
  row lighting up under a finger is a change within a screen and an identity it satisfied would pass
  on the very list this refuses.
- A screenshot is taken between two reads of the hierarchy and filed only if they agree. One capture
  whose halves are of different screens is worse than no capture.
- **Prefer a check the machine cannot outrun.** A longer timer is not a fix: it costs every walk and a
  slower machine defeats it again. An identity comparison, or a content check like
  `ScreenContentCheck`, carries no timing assumption at all.
- **Flag where the artefact is honest; refuse where it cannot be attributed.** A capture of a screen
  mid-load is a true picture of a load — flag it (`axTreeHasContent`) and let the reader see it. A
  capture under a state the device discarded cannot be attributed to anything — refuse that state.
- **A refusal costs what it names, and no more.** Refuse the states the evidence implicates and file the
  rest; widen the refusal only where the evidence cannot say which state is honest, and never let a
  partial refusal carry a passing outcome. A whole-screen refusal over one ignored dark state cost an
  app's round six screens of perfectly good light captures (SimWalk#15). **Keep a side only on two
  agreeing reasons, and refuse on any one.** A brightness floor alone kept a dark device's image-heavy
  render as light; the device's appearance alone trusted a reset made with the very setter in doubt and
  kept a dim, dark render as light. A light state is kept when the device was found light *and* its
  capture measures as a light render — a picture measurement may add a refusal, never license a keep on
  its own.
- **A walk hands the device back as it found it**, and says on the verdict when it could not.
  Whatever a walk changes on the simulator — the appearance its states set, the accessibility the
  XCUITest teardown switches off — is put back before the answer, confirmed rather than assumed.
- **Never spell a simulator tool by absolute path under `simctl spawn`.** An absolute path runs the
  *host's* binary: `/usr/bin/defaults` is macOS's, and cannot see the simulator's preference domains —
  which is what made a device preference look unreadable from inside this tool (SimWalk#8). The bare
  name resolves inside the runtime root.

## A decision the runner makes belongs in the core
`swift test` never compiles `Runner/`, so a decision written there is a decision nothing checks — and
the ones the runner makes are exactly the load-bearing ones: is this the screen we asked for, are these
two artefacts of one moment, has this screen stopped moving. So the runner keeps only what it alone can
do (read the hierarchy, take the picture, wait) and asks the core what to do next. `SettleTracker` is
the shape: a value that takes each read and returns the next move, replayable in a test against a
scripted sequence of trees. `SettleWindow`, `StateApplicationCheck`, `TypedTextLanding` and
`ScreenIdentity` are there for the same reason. Time arrives as a parameter, never as a naked `Date()`,
which is the determinism rule below applied to the one place it is easiest to break.

**A call the runner must make, and no test can see, is pinned by the compiler.** Where the runner has
to call into the core (a check before a capture, a heartbeat before a launch), make the core's next step
*require* the call's result: a token only the check can mint (`SystemAlertCheck.Clearance`,
`LiveSessionHeartbeat.Running`), or a required argument with no default (`ScreenRecord.filed`'s
`launchResets:` and `boundElements:`, `SystemTapSearch.poll`'s `springBoardShowedSheet:`). Deleting the call then stops the
runner compiling instead of leaving `swift test` green. Say in the doc comment what it does not pin: a
required `Bool` pins the call, not its honesty.

**A `DispatchSourceTimer` that must outlive whoever started it holds itself.** An unreferenced dispatch
source is freed and stops firing without an error, so a timer passed inline (`start(on:)` as an
argument) dies when the call returns. Retain it from its own handler
(`timer.setEventHandler { withExtendedLifetime(timer, beat) }`) and let `cancel()` break the cycle;
cancel on the timer's own queue (`queue.sync { timer.cancel() }`) so no beat lands after `stop()`
returns. `LiveSessionHeartbeat.backgroundTimer` is the shape, and its tests pin both.

## Form, never value
The differ reports structure — presence, order, boxes, truncation, overlap — and by definition never
flags a figure, date, or row count differing from a reference frame; the frame is fixture data.
Value questions belong to the oracle, which owns them under stated window rules. Keep the two faces
from bleeding into each other: a "differ" finding about a number is a design bug.

## Portability is a dependency direction
`SimWalkCore` must build and make sense on a machine with plain git and no project's conventions.
Anything project- or HealthKit-specific (seeding, permission choreography, the HealthKit oracle) is
a plug-in behind a core protocol. When in doubt: would this compile and read sensibly in an unrelated
monorepo? If not, it isn't core.

## Every bundle path comes from `CaptureBundleLayout`
The capture bundle is the contract on both sides of the runner boundary: the XCUITest executor writes
it from inside a test process, and the differ and oracle read it back from a plain directory. Neither
side may derive a path its own way — not by interpolating a filename, not by restating a directory
name in a manifest field. `CaptureBundleLayout` is the single generator (*one generator per
value*, applied to paths), and `StateCapture(screenID:state:)` exists so a writer cannot record a path
a reader will not look in. A filename literal outside that file is the bug, even while it agrees.

The same reasoning makes `CaptureBundleLayout.slugSegment` the one place an authored string becomes a
path component, and `screenSlug` / `CaptureState.slug` the only identities a screen and a state have on
disk. They are derived, not authored, and reduce to lowercase alphanumerics: a screen id, a locale
identifier or a Dynamic Type name must never be able to introduce a path separator, climb out of the
bundle with `..`, or differ only by case — which two directories on a case-insensitive filesystem
cannot. Anything that reduces to the same slug is the same directory, so the *validator* reports it as a
collision rather than letting the runner discover it as an overwrite. A state slug prefixes its optional
axes (`dt_`, `loc_`) rather than dropping them positionally, so two different states cannot slug alike.

A derived component is also **never empty**. `url(forRelativePath:in:)` splits on `/` and drops empty
components, so a blank screen id derived `screens//light/screen.png` and resolved to
`screens/light/screen.png` — the screen level gone and a *state* slug standing in its place, with the
stated path equal to the derived one at every check. `slugSegment` substitutes `_`, and the validators
refuse the blank id besides: the layout cannot produce a degenerate path, and nothing asks it to.

**The extension is part of the layout, not decoration.** A bundle directory ends in `.simwalk` so a
walk's output is recognisable without opening it, and `requireBundleName` enforces that on both sides —
a writer may not produce a directory nothing could recognise, and a reader may not adopt one. A
documented property that nothing checks is a property some bundle will not have; it also makes
`simwalk bundle inspect ~/Downloads` answer the question actually asked rather than "there is no
manifest here".

**This is enforced three ways, not asserted once.** (1) a lint in the maintainers' own tooling fails the build on a string literal
under `Sources/` that spells one of the bundle's own path components — whole, or as a segment of a longer
path — outside `CaptureBundleLayout.swift`. It matches the **vocabulary**, not the slash character:
flagging every literal containing `/` is over-broad (the first URL or `yyyy/MM/dd` format added anywhere
fails) and under-broad at once (the natural second speller, `appendingPathComponent("screens")`, contains
no slash). `simwalk` is the one published component deliberately not flagged, because it is also the
tool's own name; the extension has `requireBundleName` instead. (2) API shape: the raw
`StateCapture(state:screenshotPath:axTreePath:)` is internal and the derived properties are
`public private(set)`, so no caller outside the module can state or later mutate a path. (3)
`CaptureManifestValidator` asserts each stated path *equals* what the layout derives — the backstop for
the one route the other two cannot cover, since **decoding assigns stored properties directly and
never goes through any initialiser**. Checking only that a stated artefact *exists* is not enough: a
path can exist and be the wrong one (a dark capture pointing at the light screenshot), or exist outside
the bundle entirely (`../outside.png`). Both inspected as a clean pass before (3) existed.

## A bundle is written in two phases, manifest last
Outcomes are only knowable after a walk has run, so `CaptureBundleWriter` prepares directories as the
runner arrives at each state and `finalise` writes the manifest once. **The ordering is the guarantee**:
a manifest asserting `captured` that landed before its artefacts would make an interrupted run inspect
as a pass, where a directory with no manifest is refused by name. Both `finalise` and `read` check the
same two things — that the manifest does not contradict itself (`captured` with no captures, a refusal
carrying captures) and that every artefact it claims is present — so a bundle cannot be created in a
state that reading it would reject.

**A writer refuses a non-empty directory rather than clearing it.** Writing into one would let a re-run
validate on the previous run's artefacts — Friday's failed capture passing on Monday's file at the same
path, the existence check confirming a fact about the wrong walk. Refusal over clearing is the choice:
deleting files the tool did not itself just write is the wrong default for a tool pointed at arbitrary
paths, so a stale bundle is the caller's to remove.

## A manifest is held to every check its walkbook was
`CaptureManifestValidator` is not a lighter validator than `WalkbookLoader` — it is the same questions
asked of the record instead of the plan, and where the two drift the pre-flight check stops meaning
anything. Every blankness `WalkbookProblem` reports has a `CaptureManifestProblem` counterpart (walk
name, app id, build hash, walkbook hash, device, no screens, a blank screen id, a state claimed twice),
plus the two only a record can be wrong about: a walk that finished before it started, and a stated
route that contradicts the outcome beside it. A refusal reading *"does not describe a walk that could
have happened"* while accepting a nameless walk against no app, holding nothing, is not checking that.

**Where both sides ask the same question, they share the implementation, not the shape.** The screen-id
collision check lived as two twenty-line copies, and the single line where they had drifted — one
slugged the *trimmed* id where every on-disk path slugs the raw one — is what let `" today"` and
`"_today"` pass `simwalk validate`, run a whole simulator pass, and be refused only by `finalise`,
which then discarded the bundle it had just spent the walk producing. `ScreenIDCollision` and
`SlugGroup` are that one implementation; a caller drops blank ids before calling rather than trimming
the ones it keeps, because trimming asks about an id the runner will never see.

## Completed is not attempted
`ScreenRecord.routeTaken` is what the runner **completed**; an unreachable outcome's `routeTried` is
what it **attempted**, including the step that failed. Both are worth recording — how far it got, and
what it was reaching for — but two unconstrained answers to "what did the runner do" leave a reader
unable to tell which is honest, so the validator pins completed as the leading part of attempted, and
both are printed. A field a walk writes and no reader ever sees is not a record; it is a habit.

## A walkbook states its plan; it never says "whatever is there"
Validation (`WalkbookLoader`) rejects the two shapes that look permissive and are actually ambiguous:
a screen with an **empty route** (reached from wherever the last screen left off) and a screen with
**no capture states** (captured in the device's ambient appearance). Both would produce a bundle whose
manifest cannot attest to what actually ran, which is the determinism rule below expressed as a type.
Every problem names its subject — a screen id, a step index, a slug — and a load reports *all* of them
rather than the first, because an author fixing a walkbook one refusal per run is the loop this tool
exists to remove.

## Determinism
The runner executes a plan; it never improvises navigation. Anything time- or randomness-dependent
takes its inputs explicitly (no naked `Date()`/`Date.now` in core logic paths) so a walk is
reproducible and its manifest can attest what actually ran.

## A test never signals the shared test process
A test that sends a signal to its own process, or changes a signal's disposition and then raises it,
does so in an exit test (`#expect(processExitsWith:)`), never in the process the rest of the suite runs
in. Swift Testing runs a suite's tests side by side in one process, and signal state is process-wide: a
dispatch signal source hears a signal before its delivery to a thread has finished, so a handler that
puts `SIG_DFL` back can lose the race and the process dies of that signal, even one whose default is to
discard it (`SIGURG`, `SIGIO`). Every test beside it then ends unreported, with no crash report to say
why (SimWalk#133).
