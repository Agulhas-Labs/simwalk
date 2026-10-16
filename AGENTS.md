# Agent Guidelines — SimWalk

The index to working in this repo.

## Project docs
- [README.md](README.md) — the front page: what SimWalk does and how to start.
- [Docs/Reference.md](Docs/Reference.md) — every verb and walkbook key in full.
- [.agents/Project.md](.agents/Project.md) — what SimWalk is and its scope boundary (read this first).
- [.agents/PROJECT_STRUCTURE.md](.agents/PROJECT_STRUCTURE.md) — the file layout.
- [.agents/CodingGuidelines.md](.agents/CodingGuidelines.md) — conventions specific to this repo.

## Build / test / lint
- Build: `swift build`
- Test: `swift test`
- Lint: `swiftlint lint --strict --config .swiftlint.yml`; format: `swiftformat --config .swiftformat Sources Tests Runner`
  (the commit hook runs both).
- Runner build (`swift test` never compiles `Runner/`):
  `xcodebuild build-for-testing -project Runner/SimWalkRunner.xcodeproj -scheme SimWalkRunner -destination 'generic/platform=iOS Simulator' -quiet`
- First-time setup on a fresh checkout: `sh setup.sh` (installs the tools and activates the git hooks in
  `githooks/`, which run the checks above on commit and push).
