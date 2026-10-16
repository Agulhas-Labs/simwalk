# SimWalk — what it is

Deterministic UI walks of a running iOS app, served as resolved observations. A visual validation
pass has four jobs — *navigate* to every screen/state, *capture* what it shows, *compare* it against
references and data, *adjudicate* what matters — and only the fourth needs a language model. SimWalk
does the first three deterministically and compresses the fourth's input to the flagged residue,
exactly as Sift serves resolved answers instead of raw source.

## The four faces
1. **Walkbook runner** — executes a declarative walkbook (screens, routes, capture states: themes,
   Dynamic Type sizes, locales) against one simulator via an XCUITest-based executor and writes a
   capture bundle: stitched full-scroll screenshots, the accessibility tree with text-run frames,
   and a manifest (route taken, timestamps, device, app build hash, reachability results).
2. **Structural differ** — capture vs. optional reference frame, reporting *form, never value*:
   sections present/absent, order, layout boxes, truncation, wrapping, overlap, degenerate charts.
   Compact output (~50 lines/screen); each flag names the crop that shows it.
3. **Value oracle** — every on-screen figure matched against an expected value computed outside the
   app under stated window rules: `expected(figure-id, window) -> value + attribution`. The oracle
   is a protocol: it runs any program you name (`CommandOracle`). A data-source oracle, such as one
   for HealthKit, is a plug-in you write, not part of the core.
4. **Fleet plumbing** — exclusive device leases (`simwalk lease acquire`), which can clone a simulator
   (`--clone-from`) or take a physical device (`--physical`). Preparing a device's data is a plug-in,
   not part of the core.

## Scope boundary
- **Portable core.** Nothing in the core names a project's conventions or a particular app — it must run
  anywhere: plain git, no vendored conventions, no design-system assumptions.
- **Honest contract.** UNREACHABLE with the route it tried, never an empty capture; build mismatch
  refuses rather than validating a stale binary; answers state their own arithmetic; a usage log
  (`~/.simwalk/usage.jsonl`) makes adoption and failure triage ground truth, and `simwalk usage` reads
  it. The *shape* every answer takes is the shared specification in the sift repository's
  `Docs/AnswerContract.md` — header, verdict, residue, and what the answer stood in for.
- **The model stays the adjudicator.** SimWalk decides what is *there*, never what *matters*.
- **Non-goals.** Not a golden-image CI gate, not a test framework, not an autonomous bug-finder.
- **Orchestrates, never re-implements.** Build/boot/install belong to xcodebuild/simctl (or
  XcodeBuildMCP); SimWalk owns only walk/capture/diff/oracle.

Every verb and walkbook key is in [../Docs/Reference.md](../Docs/Reference.md).
