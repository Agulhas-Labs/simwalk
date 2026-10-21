//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// The exposed tools and their schemas, as `tools/list` returns them: eight for a blocking client (Claude Code), nine for a bounded one, which also lists `walk_status`.
///
/// **Every description here is spent in every session, whether or not the tool is ever called**, so each says the two things that decide a call — what to reach for it *for*, and what it is reached for *instead of* — and stops. The long version is the agent guide, which loads only when a walkbook, capture bundle or UI-test file is open.
struct MCPToolCatalog {
    /// What `tools/list` returns for a client in `mode`.
    static func tools(for mode: MCPClientMode) -> [[String: Any]] {
        switch mode {
        case .blocking: blockingTools
        case .bounded: blockingTools.map(boundedWalk) + [walkStatus]
        }
    }

    /// The names `tools/list` returns for `mode`, in order.
    static func toolNames(for mode: MCPClientMode) -> [String] {
        tools(for: mode).compactMap { $0["name"] as? String }
    }

    private static var blockingWalkSentence: String {
        "A walk takes minutes and nothing is served until it finishes; the answer names"
    }

    private static var boundedWalkSentence: String {
        "A walk takes minutes, and a call answers within the budget with either the answer or a handle to poll with walk_status; the answer names"
    }

    /// `walk` for a bounded client: today's description with the one sentence replaced; every other tool as it is.
    private static func boundedWalk(_ tool: [String: Any]) -> [String: Any] {
        guard tool["name"] as? String == SimWalkTool.walk.rawValue, let description = tool["description"] as? String else { return tool }
        var bounded = tool
        bounded["description"] = description.replacingOccurrences(of: blockingWalkSentence, with: boundedWalkSentence)
        return bounded
    }

    private static var walkStatus: [String: Any] {
        [
            "name": SimWalkTool.walkStatus.rawValue,
            "description": "Poll a walk that 'walk' answered with a handle: waits up to the budget, then returns the walk's answer if it has ended, else one running line with its progress.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "handle": ["type": "string", "description": "the handle that 'walk' returned on its running line"],
                ],
                "required": ["handle"],
            ],
        ]
    }

    private static var blockingTools: [[String: Any]] {
        [
            [
                "name": SimWalkTool.walk.rawValue,
                "description": "Call this instead of tapping through the simulator by hand: it drives the app through a walkbook (screens, the route to each, the states to capture) on one simulator (or a physical iPhone or iPad, by 'device' UDID) and writes a capture bundle, then answers what it reached and what it refused. A walk takes minutes and nothing is served until it finishes; the answer names every screen the app did not have where the walkbook said, so a screenshot is opened only for a screen it flags. Pass 'dryRun' to check that every screen's route still resolves, in seconds per screen, without capturing anything — the cheap check to run after app changes, before spending a full walk.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "walkbook": ["type": "string", "description": "Path to a walkbook JSON file."],
                        "output": ["type": "string", "description": "Where to write the capture bundle — a directory ending in .simwalk that does not already exist. With 'dryRun', where to write the route-probe report instead — a .json file that does not already exist."],
                        "device": ["type": "string", "description": "Simulator name or UDID — or the UDID of a physical iPhone or iPad `xcrun devicectl list devices` shows, which walks that device (needs 'team'; no 'dryRun'). Defaults to a booted simulator, else the newest available — never one another caller has leased. A walk reboots only a device leased to it, named by UDID, or booted by the walk."],
                        "lease": ["type": "string", "description": "A lease token from `simwalk lease acquire` (with --physical for a phone): walk the leased device, which is this walk's to reboot. Instead of 'device'."],
                        "appPath": ["type": "string", "description": "An .app bundle to install before walking. Omit when the app is already installed. On a physical device the install replaces the phone's copy, which is not restored."],
                        "team": ["type": "string", "description": "Physical device only, and required there: the Apple signing team ID the runner is built under. Refused on a simulator walk."],
                        "runnerBundleId": ["type": "string", "description": "Physical device only: the runner's bundle identifier, when the default is not one your team can sign. Refused on a simulator walk."],
                        // Named for what it holds rather than after the walkbook's own field: it is a list of
                        // ids, and `screens` is a capture bundle's directory name, which nothing outside
                        // `CaptureBundleLayout` may spell (the repo's `derived_bundle_path` rule).
                        "screenIDs": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Walk only these screen ids, in walkbook order. The bundle records the subset as the plan it ran, so it does not stand in for a full walk.",
                        ],
                        "settle": ["type": "integer", "description": "How long the screen must hold still before each capture, in milliseconds. Raise it for content that streams in after the screen appears."],
                        "animations": ["type": "boolean", "description": "Keep UIKit animations on in the app under walk. A simulator walk switches them off by default; a walk that records motion keeps them on."],
                        "motion": ["type": "boolean", "description": "Record on every screen's captures when the tree last changed before the capture (settle time, ms), with the read cadence and read count — the resolution of that figure. A screen asks for it alone with \"motion\": true in the walkbook. Absent from a capture means motion was not recorded, never that there was none."],
                        "appleAudit": ["type": "boolean", "description": "Record Apple's accessibility audit on every state's capture (apple-audit.json), after the capture; about 2 s a state on a simulator, and the audit moves scroll position, so it runs last. A walkbook asks for it alone with \"appleAudit\": true. Absent from a capture means it was not audited, never that it was clean."],
                        "stock": ["type": "boolean", "description": "Boot a device SimWalk created (a `lease acquire` with `cloneFrom`) with every launchd service on. Without it, such a device boots with the services the app at appPath does not need switched off, and the answer says so on a `device:` line. Refused for a device that SimWalk did not create and that has services off, and for a physical device."],
                        "dryRun": ["type": "boolean", "description": "Follow every screen's route against the booted app and report each step that no longer lands, capturing nothing. Writes a route-probe report to 'output' instead of a capture bundle."],
                        "verbose": ["type": "boolean", "description": "Write the full result file: every state, every route taken."],
                    ],
                    "required": ["walkbook", "output"],
                ],
            ],
            [
                "name": SimWalkTool.validate.rawValue,
                "description": "Call this before a walk, instead of finding out on the simulator: it answers whether a walkbook parses and can be executed as written, naming every problem at once rather than the first. Seconds, where a walk costs minutes — but it checks the plan and never the app, so a route naming a control this build no longer renders still validates.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "walkbook": ["type": "string", "description": "Path to a walkbook JSON file."],
                        "device": ["type": "boolean", "description": "Apply the device target's rules too (a walk on a physical iPhone or iPad): whatever such a walk would refuse — a locale, a location, resetPermissions, a walk-level setup — is a problem here."],
                    ],
                    "required": ["walkbook"],
                ],
            ],
            [
                "name": SimWalkTool.inspect.rawValue,
                "description": "Call this instead of opening a capture bundle's screenshots and accessibility trees: it answers what the walk reached, what it refused and with which route, and what is on disk. Pass 'step' to read one screen's content instead — its screen identifier and the text inside the screenshot's frame, in accessibility order, narrowed by 'match' (inside the frame, not unobscured: text under a bar or behind a sheet still counts); that is the text half of what a screenshot shows, and a shape question (a capsule vs. a line) still needs the screenshot. A navigation bar's title stands in for the identifier only when nothing else names the screen, and says it is localised. This is how to read a bundle somebody else's walk wrote, or one written before the current change.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "bundle": ["type": "string", "description": "Path to a capture bundle directory."],
                        "step": ["type": ["integer", "string"], "description": "Read one screen instead of the whole manifest: its 1-based position in the walk (as this tool numbers screens in its own listing), or the screen's own id."],
                        "state": ["type": "string", "description": "With 'step': which of the screen's captured states to read, by slug (for example 'light' or 'dark'). With none named, a screen holding several answers for the first and names the others."],
                        "match": ["type": "string", "description": "With 'step': only the text elements whose label or value contains this (case-insensitive), on screen or off it; off-screen hits come after the on-screen ones, marked."],
                        "all": ["type": "boolean", "description": "With 'step': list the off-screen elements too, after the on-screen ones, each marked '(off screen)'."],
                        "tree": ["type": "boolean", "description": "With 'step' and 'match': list the nodes 'match' names (text, identifier or type) with identifier, frame, selected flag and ancestor chain, instead of the text. Needs 'match' unless 'bars' is set."],
                        "bars": ["type": "boolean", "description": "With 'step': list the tab bars, toolbars and navigation bars with their frames; alone, or with 'tree' and 'match' for the union."],
                    ],
                    "required": ["bundle"],
                ],
            ],
            [
                "name": SimWalkTool.audit.rawValue,
                "description": "Call this instead of reading a bundle's accessibility trees: it runs every audit rule over the bundle by default — disclosure rows not typed as controls, enabled controls with neither label nor identifier, controls labelled with an SF Symbol name, and one label shared by distinct controls on a screen — one section per rule. Over a bundle whose walk recorded Apple's accessibility audit (appleAudit), seven apple* rules report Apple's own findings per state, and say \"not recorded\" otherwise. It reports form, never value, and it says which screens it could not cover.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "bundle": ["type": "string", "description": "Path to a capture bundle directory."],
                        "only": [
                            "type": "array",
                            "items": ["type": "string", "enum": AuditRuleName.allCases.map(\.rawValue)],
                            "description": "Run only these rules. Omit for every rule.",
                        ],
                        "walkbook": ["type": "string", "description": "Path to a walkbook whose screens state 'budgets': the motionBudget rule holds the recorded motion to settleMs and layoutShifts, and the performanceBudget rule holds the performance a device walk measured to launchMs, transitionHitches, cpuMs and memoryPeakMB (a simulator bundle has none: UNREACHABLE). Without budgets for a rule it prints 'not run' in a full run, and 'only' naming it is refused."],
                    ],
                    "required": ["bundle"],
                ],
            ],
            [
                "name": SimWalkTool.diff.rawValue,
                "description": "Call this instead of opening two walks' screenshots side by side: it compares a run bundle against a reference bundle by form, never value — sections present on one side only, sections in a different order, sections whose box moved or resized, and layout shifts present on one side only (walks with motion on), and Apple accessibility-audit issues the run has and the reference lacks, by element and never frame (walks that ran Apple's audit) — and says which screens it could not compare. Each form flag names a crop of the screenshot that shows it; pass 'crops' to write them as PNGs, then open only the crops a flag names.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "reference": ["type": "string", "description": "Path to the reference capture bundle."],
                        "run": ["type": "string", "description": "Path to the capture bundle compared against the reference."],
                        "crops": ["type": "string", "description": "A directory, new or empty, to write one PNG per flag crop into. Omit to get the flags without files."],
                    ],
                    "required": ["reference", "run"],
                ],
            ],
            [
                "name": SimWalkTool.oracle.rawValue,
                "description": "Call this instead of reading a bundle's screenshots to check a number: it reads each figure the walkbook names off the captured screens and asks the walkbook's value oracle command what it should be, under every window named. One line per figure per state: which window the on-screen figure matches (all windows listed with their values), or matches none, not on screen, no readable number, or oracle failed. It says which figures sit on screens that were not captured, and when the walkbook is not the one the bundle was walked from.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "bundle": ["type": "string", "description": "Path to the capture bundle."],
                        "walkbook": ["type": "string", "description": "Path to the walkbook JSON carrying 'oracle' and each screen's 'figures'."],
                    ],
                    "required": ["bundle", "walkbook"],
                ],
            ],
            [
                "name": SimWalkTool.session.rawValue,
                "description": "Call this to explore a running app warm instead of paying a runner launch per look: 'start' holds a resident runner on a simulator or physical iPhone/iPad you own and prints an id; 'read' answers inspect's screen and a 'screen <hash>'; 'step' takes one walkbook route step as a walk takes it, guarded by that hash (a stale guard is refused, nothing done), and answers the landed step and what changed; 'save' writes the landed steps as a walkbook screen a walk replays — before 'end', which removes the session; 'list' shows the machine's sessions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["start", "read", "step", "save", "end", "list"], "description": "What to do."],
                        "app": ["type": "string", "description": "start: the bundle id of the installed app."],
                        "device": ["type": "string", "description": "start: the UDID of a booted simulator that is yours, or of a paired physical iPhone or iPad (then 'team' is required), which the session leases. Or 'lease'."],
                        "lease": ["type": "string", "description": "start: a lease token from `simwalk lease acquire`."],
                        "state": ["type": "object", "description": "start: a capture state (a walkbook 'states' entry) to launch under."],
                        "team": ["type": "string", "description": "start, physical device only, and required there: the Apple signing team ID the runner is built under. Refused on a simulator."],
                        "runnerBundleId": ["type": "string", "description": "start, physical device only: the runner's bundle identifier, when the default is not one your team can sign. Refused on a simulator."],
                        "animations": ["type": "boolean", "description": "start: keep UIKit animations on in the app. A simulator session switches them off by default."],
                        "id": ["type": "string", "description": "read, step, save, end: the session id start printed."],
                        "match": ["type": "string", "description": "read: only the text elements whose label or value contains this."],
                        "step": ["type": "object", "description": "step: one walkbook route step, e.g. {\"tap\":{\"label\":\"Next\"}}."],
                        "guard": ["type": "string", "description": "step: the screen hash a read printed."],
                        "screen": ["type": "string", "description": "save: the id the saved screen takes."],
                        "into": ["type": "string", "description": "save: the walkbook to create, or to append the screen to (re-encoded)."],
                        "expect": ["type": "string", "description": "save: the identifier the reached screen carries."],
                        "since": ["type": "integer", "description": "save: only the steps from this request number on."],
                    ],
                    "required": ["action"],
                ],
            ],
            [
                "name": SimWalkTool.mirror.rawValue,
                "description": "Call this instead of screenshotting iPhone Mirroring to see or drive a real iPhone. Every action re-activates Mirroring and refuses, naming what was frontmost, unless it is frontmost (exit 3: retry). 'read' answers the screen; 'tap', 'swipe', 'scroll' and 'menu' act, then answer what the screen settled on; 'burst' taps then takes 1-60 frames to see a transition. Positions are fractions 0-1 of the mirroring window: the answer's line boxes give them, so tap a line's centre x,y. Answers are OCR text lines with boxes, '+' lines new since the action, 'gone:' what went; when no text changed the answer is qualified, not a success. The screenshot's path is in every answer: read that file only when the pixels matter. It never types. A drag does not scroll inside an app: use 'scroll' (positive lines reveal what is below, or to the right with 'horizontal'). 'menu' item 'home' from the App Switcher takes two calls. Never tap anything that deletes, signs out or disconnects.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["read", "tap", "swipe", "scroll", "menu", "burst"], "description": "What to do."],
                        "at": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2, "description": "tap, burst: [x, y] fractions of the window. swipe: where it starts. scroll: where the pointer is (default [0.5, 0.5])."],
                        "to": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2, "description": "swipe: [x, y] where it ends."],
                        "ms": ["type": "integer", "description": "swipe: how long the drag takes, 50-5000 (default 350)."],
                        "lines": ["type": "integer", "description": "scroll: wheel lines, 1-50 in magnitude; positive reveals what is below (or to the right), negative what is above."],
                        "horizontal": ["type": "boolean", "description": "scroll: sideways instead of down."],
                        "item": ["type": "string", "enum": ["home", "switcher"], "description": "menu: Home Screen or App Switcher."],
                        "frames": ["type": "integer", "description": "burst: how many frames, 1-60."],
                        "sheet": ["type": "boolean", "description": "burst: also write sheet.png, the frames tiled and labelled by time."],
                        "match": ["type": "string", "description": "read, tap, swipe, scroll, menu: only the text lines that contain this."],
                        "settleMs": ["type": "integer", "description": "read, tap, swipe, scroll, menu: the longest to wait for the screen to settle (default 3000)."],
                        "out": ["type": "string", "description": "A directory to keep the captures in, unpruned."],
                    ],
                    "required": ["action"],
                ],
            ],
        ]
    }
}
