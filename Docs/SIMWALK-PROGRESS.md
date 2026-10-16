# Progress and result file formats

A long walk or live session writes two small JSON files you can read while it runs and after it ends. The progress file shows where the run is now. The result file lists what happened once it is over. Read them to build a status line, a dashboard, or a script that follows a walk. You do not need to ask the tool anything: poll the files.

## 1. Where

| File | Path | Written |
|---|---|---|
| Progress | `~/.simwalk/progress/<session>.json` | during a run, atomically |
| Result | `~/.simwalk/progress/<session>.result.json` | once, when the run ends |

`<session>` is the value of the `CLAUDE_CODE_SESSION_ID` environment variable. A run without one, such as a human's CLI call, uses `default`. Files are per session, never per project, so parallel sessions in sibling worktrees do not share one. The directory is the one that holds the usage log (`~/.simwalk/`). `SIMWALK_USAGE_LOG` moves the log, and the progress directory moves with it.

Two runs alive at once never share a file (SimWalk#83). Each run takes a lock on `<session>.lock` for as long as it lives. A run that finds it held takes the next free slot: `<session>.2.json` and `<session>.2.result.json`, then `.3`, and so on. A session id never contains a dot, so a slot never names another session's file. The system drops the lock when the process dies, so a killed run does not block a slot. Slots are reused, so the directory holds a few files per session, not a pair per run.

A live session (`tool: "session"`) starts at slot 2. Slot 1 stays free for a walk.

To find the right files:

- The `walk` answer ends with a `result: <path>` line, and the progress file's `resultPath` names the result file.
- To find every live run of a session, glob `<session>.*.json` and drop every match that ends in `.result.json`. That glob also matches result files.
- A live session holds its slot until it ends, or until it has been idle past its timeout.

## 2. Progress schema (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "tool": "walk",
  "phase": "running",
  "pid": 4242,
  "startedAt": "2027-10-02T09:00:00.000Z",
  "updatedAt": "2027-10-02T09:00:41.250Z",
  "device": { "name": "iPhone 17", "udid": "…", "osVersion": "26.5" },
  "app": "com.example.App",
  "currentStep": { "index": 4, "total": 12, "action": "walk login", "screen": "login" },
  "matches": { "planned": 12, "passed": 3, "failed": 0, "pending": 9 },
  "lastScreenshotPath": "/abs/path/Out.simwalk/screens/home/light/screenshot.png",
  "summary": { "bootMs": 8200, "installMs": 900, "buildMs": 31000, "runMs": null },
  "logPath": "/Users/…/.simwalk/usage.jsonl",
  "resultPath": null,
  "error": null
}
```

Every key except `schemaVersion`, `tool`, `phase`, `pid`, `startedAt` and `updatedAt` may be `null` or absent. `logPath` is set from the first write, so it is there from `booting` on, even for a run that is refused while preparing.

- `tool`: `walk`, `walk --dry-run` or `session`.
- `phase`: `idle`, `booting`, `installing`, `building`, `launching`, `running`, `matching`, `done` or `failed`. A walk moves through them in that order. `done` and `failed` are final and stay until the next run.
  - `building` is the runner's build. `launching` runs from the end of that build until the runner reports `running`. It covers the setup in the walkbook (permissions, status bar and the like) and starting the runner and the app. `running` means the runner is walking screens. `matching` is the tool reading the capture bundle back.
  - A dry run has no `launching`. It goes straight to `running`, then `done` or `failed`, with no per-screen progress and no result file.
- `currentStep`: one screen of the walkbook, not one tap. `index` starts at 1. `total` is the number of screens the run executes, and it is absent for `session`, where an agent drives the steps one by one, so show the index alone. `index` is `0` between the plan and the first screen, so show no step until it is 1 or more. `action` is a short human line. It never carries typed text (`type into '<label>'`), and a URL is cut down to its scheme and host (`openURL 'https://example.com/…'`, `openURL 'myapp:…'`), because both can hold secrets (SimWalk#90, SimWalk#91).
- `matches`: screens counted by outcome, updated as each screen finishes. `planned` is the screens the run executes. `passed` is the screens captured as the walkbook said. `failed` is every other outcome (`unreachable`, `unexpectedScreen`, `stateNotApplied`, `captureFailed`, `buildMismatch`). `pending` is the rest. A walk compares no screenshots. "Match" means the screen was reached and captured. The `diff` verb compares bundles, by form and not by value, and reports no pixel percentage.
- `summary`: wall-clock milliseconds per segment, filled in as each one ends.
  - `bootMs` is the simulator boot and wait.
  - `installMs` is the app install, when `appPath` is given.
  - `buildMs` is the runner's `build-for-testing`. It is cached after the first run and is not your app's build.
  - `runMs` is the whole `xcodebuild test-without-building` call. It includes launching the runner and the app, and it ends before the `matching` phase.
  - A slow `bootMs` is the simulator. A slow `runMs` is the app or its launch.
- `pid` and `updatedAt`: if the phase is not final and the `pid` is dead, or `updatedAt` is more than 30 seconds old with no live `pid`, treat the run as over. A killed run usually dies without a chance to write anything, so this check is how you spot one.

## 3. Cadence and lifecycle

- Each write is atomic: the tool writes a temp file in the same directory, then renames it. A reader sees the old file or the new one, never a torn one. Do not write these files yourself.
- Writes are throttled to one per 500 ms. Every phase change, every finished screen, completion and failure are always written.
- One writer at a time. The tool writes `booting` to `launching`. The runner writes `running` and each finished screen, so the step moves on the moment a screen ends. The tool then reads the file back and writes `matching`, then `done` or `failed`.
- The final phase is `done` only when every screen passed. A walk with a failed screen, or one that was refused, ends `failed`. Read `verdict` in the result file for the reason.
- At the end the result file is written first, and `resultPath` is set in the same write that makes the phase final.
- An error that ends the run writes `failed` with an `error` message.
- A cancelled run writes `failed` with `error: "cancelled"`. It does so for a client's cancel request on the MCP server, and for SIGTERM or SIGINT on the CLI (SimWalk#83, SimWalk#85). Once cancelled, the file stays `failed` and `cancelled`, even if the runner writes again. To carry the cancel to the runner, the tool first creates an empty marker beside the file, `<progress>.cancel` (for example `<session>.json.cancel`). No `*.json` glob matches it (SimWalk#87, SimWalk#89). The screen counts stay in the file.
- A new run overwrites the file from `booting`. Nothing accumulates.
- A session's runner rewrites `heartbeat.json` (`{"at": …, "interval": 2}`) in its session directory every 2 s. A runner gone without `exit.json` is taken to have stopped no later than `at + 3 × interval`.

### The `session` tool

A session is one run that spans many calls (SimWalk#83).

- `session start` writes the file with `tool: "session"`, in `building`. A session boots and installs nothing. It refuses a device that is not booted or an app that is not installed. It then writes `device` and `app`, and `launching` until the runner is ready.
- The resident runner takes the file over. It writes `running` once the app is launched, and the phase stays `running` between steps. Every `step` request moves `currentStep` on, counted from 1, with no `total`. `action` is the step as a route shows it, such as `tap 'Next'`. Reads, saves and `list` write nothing. Nothing writes `matches`.
- The runner ends the file. It writes `done` for `end` or the idle timeout, and `failed` with the detail when it could not launch or serve. A session has no result file and no `summary`.
- From the moment the runner starts, `pid` is the `xcodebuild` process that hosts it. If that process dies, the session is over, and the 30-second rule in section 2 reads it as dead.
- Cancelling `start` ends the file `failed` with `error: "cancelled"`, even if the session still comes up. Cancelling `step`, `read` or `end` changes nothing.

## 4. Result schema (`schemaVersion` 1)

`<session>.result.json` is a compact summary of a finished walk, built for rendering a list of its steps. It is capped at 16 KiB.

```json
{
  "schemaVersion": 1,
  "tool": "walk",
  "verdict": "failed",
  "walkName": "…", "app": "com.example.App", "device": { "name": "…", "udid": "…", "osVersion": "…" },
  "bundlePath": "/abs/Out.simwalk",
  "logPath": "/abs/usage.jsonl",
  "timings": { "bootMs": 8200, "installMs": 900, "buildMs": 31000, "runMs": 52000, "totalMs": 95000 },
  "counts": { "planned": 12, "passed": 11, "failed": 1 },
  "steps": [
    { "index": 1, "screen": "home", "outcome": "passed", "screenshotPath": "/abs/…/screenshot.png" },
    { "index": 4, "screen": "login", "outcome": "failed", "kind": "unexpectedScreen", "reason": "…" }
  ],
  "failures": [
    { "index": 4, "screen": "login", "kind": "unexpectedScreen", "reason": "…",
      "expected": "login", "actual": ["welcome"], "screenshotPath": "/abs/…/screenshot.png" }
  ],
  "truncated": { "omittedSteps": 0, "clippedFailures": 0 }
}
```

- `verdict` is `passed`, `failed` or `refused`. A step's `outcome` is `passed` or `failed`. `kind` is the failure's outcome name, as in the `matches` list above.
- `expected` and `actual` are the screen identifiers the walkbook expected and the ones the screen showed (`unexpectedScreen`). An `unreachable` failure has the last route step it was reaching for as `expected`, and no `actual`. The whole route it tried is in `reason`. `screenshotPath` is the capture of what the screen actually showed, as an absolute path. There is no reference screenshot and no diff percentage, because a walk has no reference.
- `steps` lists every screen in walkbook order. When the 16 KiB cap bites, passed steps are dropped from the end first, then failed ones. `truncated.omittedSteps` counts both. A dropped failed step stays in full in `failures`.
- If the file is still over the cap, each failure's `reason`, `expected` and each `actual` entry are clipped to 512 characters, ending in `…`. `truncated.clippedFailures` counts the failures changed. An older file may omit it, so read a missing value as 0. Entries in `failures` are never dropped, so a walk with enough failures can pass 16 KiB.
- `verbose` (CLI `--verbose`, MCP `verbose`) lifts the cap and adds each step's `states` (slug, screenshot and tree paths) and `routeTaken`.
- The text answer a tool returns ends with one extra line, `result: <path>`.

## 5. Which tools write progress

Only the two long-running tools write progress: `walk`, which takes minutes, and `session`, where `start` is slow and steps are not. `validate`, `inspect`, `audit`, `diff` and `oracle` take seconds and write none. In Claude Code, one hook matcher covers both: `^mcp__simwalk__(walk|session)$`.
