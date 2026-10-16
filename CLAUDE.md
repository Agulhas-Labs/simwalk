# Claude Code Configuration — SimWalk

Start at **[AGENTS.md](AGENTS.md)** — the index to all agent guidelines (project structure, build/test,
coding rules). Read the files it links before starting a task.

## Always
- **Verify before concluding**: `swift build` + `swift test` pass, the whole tree lints clean
  (`swiftlint lint --strict --config .swiftlint.yml` — the pre-commit hook lints only changed files, so a
  violation in an untouched file waits for the next person to edit it, SimWalk#82), SwiftFormat leaves no
  diff (`swiftformat --config .swiftformat Sources Tests Runner`), the runner still builds
  (`xcodebuild build-for-testing -project Runner/SimWalkRunner.xcodeproj -scheme SimWalkRunner
  -destination 'generic/platform=iOS Simulator' -quiet` — `swift test` never compiles `Runner/`), and every
  changed file conforms to [.agents/CodingGuidelines.md](.agents/CodingGuidelines.md). The git hooks
  (`githooks/`, set up by `sh setup.sh`) run the same checks on commit and push; they are the backstop,
  so don't rely on them.
- **Edit SimWalk in a separate git worktree, never in the checkout you install from.** `install-hook`
  snapshots the walk runner from the checkout the binary was compiled from — whatever that checkout holds
  at that moment, edits and untracked files included — and pairs the snapshot with the binary for good
  (SimWalk#16). The checkout deploys are built from is where a half-made edit would ship to every walk on
  the machine. `git worktree add ../SimWalk-<topic> <branch>` and work there; the install checkout stays
  on a clean `main`.
- **Commit self-contained, verified units** (compiles, tests pass, lint clean) with a clear, well-scoped
  message; keep unrelated changes in separate commits.
- **Installing a build.** A merge leaves `~/.local/bin/simwalk` stale until the tool is installed. Run
  this **from the repo root** on a clean checkout of the build you want, then smoke-test with a walk:
  ```sh
  swift build -c release
  rm -f ~/.local/bin/simwalk                       # NEVER cp over the existing file
  cp .build/release/simwalk ~/.local/bin/simwalk
  simwalk install-hook
  ```
  **`rm` before `cp`**: copying over the old file gets the new binary killed on launch, with no message.
  `install-hook` pairs the binary with a snapshot of the walk runner taken from the checkout it was built
  from, so build and install back to back, from a clean checkout. It also registers the MCP server, status
  line, `PreToolUse` hook and agent guide. The flags are in `Docs/Reference.md` (install-hook).
- **Where a new convention goes**: *mechanical / checkable* → a lint rule, not a regex, not prose; *a
  repeatable procedure* → a skill; *judgment / architecture / preference* → the relevant `.agents/` md
  file; *a file-layout change* → also update [.agents/PROJECT_STRUCTURE.md](.agents/PROJECT_STRUCTURE.md).

## Project shape
One binary, two faces: `simwalk` is a CLI for humans and an MCP stdio server for coding agents, serving
deterministic UI walks of a running iOS app as **resolved observations** — capture bundles, structural
diffs (*form, never value*), and value-oracle parity answers — with an honest contract on every answer
(UNREACHABLE names the route it tried; a build mismatch refuses rather than validating a stale binary).
`SimWalkCore` owns the walkbook model, capture bundles, differ, and oracle protocol; both front ends stay
thin. The docs are [README.md](README.md) (the front page) and [Docs/Reference.md](Docs/Reference.md) (every
verb and walkbook key); [.agents/Project.md](.agents/Project.md) states the scope boundary. Two rules
carved in stone: the core assumes no project's conventions (plain git, no design-system assumptions;
project-specific pieces are plug-ins), and the MCP server's stdout carries JSON-RPC only.
