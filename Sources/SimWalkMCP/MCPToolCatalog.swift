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
                "description": "Call this instead of tapping through the simulator by hand: it drives the app through a walkbook on a simulator or physical device, writes a capture bundle, and answers what it reached and refused. A walk takes minutes and nothing is served until it finishes; the answer names every screen the app lacked. 'dryRun' is the cheap check.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "walkbook": ["type": "string", "description": "Path to a walkbook JSON file."],
                        "output": ["type": "string", "description": "Bundle directory to write (ends in .simwalk, must not exist); with 'dryRun', a new .json report."],
                        "device": ["type": "string", "description": "Simulator name or UDID, or a physical device UDID (needs 'team', no 'dryRun')."],
                        "lease": ["type": "string", "description": "Token from `simwalk lease acquire`: walks that device. Instead of 'device'."],
                        "appPath": ["type": "string", "description": "An .app bundle to install first; on a physical device it replaces the phone's copy."],
                        "team": ["type": "string", "description": "Physical device only, and required there: the Apple signing team ID the runner is built under."],
                        "runnerBundleId": ["type": "string", "description": "Physical device only: the runner's bundle id, if the default is not one your team can sign."],
                        // Named for what it holds rather than after the walkbook's own field: it is a list of
                        // ids, and `screens` is a capture bundle's directory name, which nothing outside
                        // `CaptureBundleLayout` may spell (the repo's `derived_bundle_path` rule).
                        "screenIDs": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Walk only these screen ids; the bundle records the subset, so it is not a full walk.",
                        ],
                        "settle": ["type": "integer", "description": "Milliseconds the screen must hold still before each capture."],
                        "animations": ["type": "boolean", "description": "Keep UIKit animations on (a simulator walk switches them off by default)."],
                        "motion": ["type": "boolean", "description": "Record when each capture's tree last changed (ms), with the read cadence and count."],
                        "appleAudit": ["type": "boolean", "description": "Record Apple's accessibility audit per state (apple-audit.json); about 2 s a state."],
                        "stock": ["type": "boolean", "description": "Boot a SimWalk-created device (`lease acquire` with `cloneFrom`) with every launchd service on."],
                        "dryRun": ["type": "boolean", "description": "Follow each screen's route against the booted app and report steps that no longer land; captures nothing."],
                        "verbose": ["type": "boolean", "description": "Write the full result file: every state and route."],
                    ],
                    "required": ["walkbook", "output"],
                ],
            ],
            [
                "name": SimWalkTool.validate.rawValue,
                "description": "Call this before a walk, instead of finding out on the simulator: it answers whether a walkbook parses and can be executed as written, naming every problem at once. Seconds, where a walk costs minutes, but it checks the plan and never the app.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "walkbook": ["type": "string", "description": "Path to a walkbook JSON file."],
                        "device": ["type": "boolean", "description": "Apply the physical-device target's rules too: whatever such a walk would refuse is a problem here."],
                    ],
                    "required": ["walkbook"],
                ],
            ],
            [
                "name": SimWalkTool.inspect.rawValue,
                "description": "Call this instead of opening a bundle's screenshots and accessibility trees: it answers what the walk reached, what it refused (and the route), and what is on disk. 'step' reads one screen's text inside the screenshot's frame (not unobscured: text under a bar or sheet counts); shapes need the screenshot. A navigation bar's title names a screen only as a last resort, and says it is localised.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "bundle": ["type": "string", "description": "Path to a capture bundle directory."],
                        "step": ["type": ["integer", "string"], "description": "Read one screen instead of the manifest: its 1-based position in the walk, or its own id."],
                        "state": ["type": "string", "description": "With 'step': which captured state to read, by slug (e.g. 'light'). Default: the first, naming the others."],
                        "match": ["type": "string", "description": "With 'step': only elements whose label or value contains this (case-insensitive), on or off screen."],
                        "all": ["type": "boolean", "description": "With 'step': list the off-screen elements too, after the on-screen ones, each marked."],
                        "tree": ["type": "boolean", "description": "With 'step' and 'match': the matched nodes with identifier, frame, selected flag and ancestors, not the text."],
                        "bars": ["type": "boolean", "description": "With 'step': the tab bars, toolbars and navigation bars with frames; alone, or with 'tree' and 'match'."],
                    ],
                    "required": ["bundle"],
                ],
            ],
            [
                "name": SimWalkTool.audit.rawValue,
                "description": "Call this instead of reading a bundle's accessibility trees: it runs every audit rule, one section per rule: disclosure rows not typed as controls, enabled controls with no label or identifier, controls labelled with an SF Symbol name, one label on distinct controls. Seven apple* rules report Apple's own audit, where recorded. Form, never value; it says which screens it could not cover.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "bundle": ["type": "string", "description": "Path to a capture bundle directory."],
                        "only": [
                            "type": "array",
                            "items": ["type": "string", "enum": AuditRuleName.allCases.map(\.rawValue)],
                            "description": "Run only these rules. Omit for every rule.",
                        ],
                        "walkbook": ["type": "string", "description": "A walkbook whose screens state 'budgets', for the motionBudget and performanceBudget rules."],
                    ],
                    "required": ["bundle"],
                ],
            ],
            [
                "name": SimWalkTool.diff.rawValue,
                "description": "Call this instead of opening two walks' screenshots side by side: it compares a run bundle against a reference by form, never value: sections on one side only, reordered, moved or resized; layout shifts on one side only; Apple audit issues only the run has. It says which screens it could not compare. Each flag names a screenshot crop; pass 'crops' to write PNGs and open only those.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "reference": ["type": "string", "description": "Path to the reference capture bundle."],
                        "run": ["type": "string", "description": "Path to the capture bundle compared against the reference."],
                        "crops": ["type": "string", "description": "A new or empty directory for one PNG per flag crop. Omit to get the flags without files."],
                    ],
                    "required": ["reference", "run"],
                ],
            ],
            [
                "name": SimWalkTool.oracle.rawValue,
                "description": "Call this instead of reading a bundle's screenshots to check a number: it reads each figure the walkbook names off the captured screens and asks the walkbook's value oracle command what it should be, under every window named. One line per figure per state, saying which window the on-screen figure matches, or none; it names the figures on screens that were not captured.",
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
                "description": "Call this to explore a running app warm instead of paying a runner launch per look: 'start' holds a resident runner on a simulator or physical device you own and prints an id; 'read' answers inspect's screen and a 'screen <hash>'; 'step' takes one route step guarded by that hash (a stale guard is refused); 'save' writes the landed steps as a walkbook screen, before 'end'; 'list' shows sessions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["start", "read", "step", "save", "end", "list"], "description": "What to do."],
                        "app": ["type": "string", "description": "start: the bundle id of the installed app."],
                        "device": ["type": "string", "description": "start: UDID of a booted simulator that is yours, or a paired physical device (needs 'team'). Or 'lease'."],
                        "lease": ["type": "string", "description": "start: a lease token from `simwalk lease acquire`."],
                        "state": ["type": "object", "description": "start: a walkbook 'states' entry to launch under."],
                        "team": ["type": "string", "description": "start, physical device only, and required there: the Apple signing team ID the runner is built under."],
                        "runnerBundleId": ["type": "string", "description": "start, physical device only: the runner's bundle id, if the default is not one your team can sign."],
                        "animations": ["type": "boolean", "description": "start: keep UIKit animations on (a simulator session switches them off by default)."],
                        "id": ["type": "string", "description": "read, step, save, end: the id start printed."],
                        "match": ["type": "string", "description": "read: only the text elements whose label or value contains this."],
                        "screenshot": ["type": "boolean", "description": "read: also write a PNG (point scale, about 450 tokens to view); its path is on a 'screenshot:' line."],
                        "screenshotScale": ["type": "integer", "description": "read: pixels per point, 1, 2 or 3 (default 1); implies 'screenshot'."],
                        "screenshotOf": ["type": "string", "description": "read: crop to the element with this label plus 8 pt; implies 'screenshot'."],
                        "step": ["type": "object", "description": "step: one walkbook route step, e.g. {\"tap\":{\"label\":\"Next\"}}."],
                        "guard": ["type": "string", "description": "step: the screen hash a read printed."],
                        "screen": ["type": "string", "description": "save: the id the saved screen takes."],
                        "into": ["type": "string", "description": "save: the walkbook to create or append the screen to (the whole file is re-encoded)."],
                        "expect": ["type": "string", "description": "save: the identifier the reached screen carries."],
                        "since": ["type": "integer", "description": "save: only the steps from this request number on."],
                    ],
                    "required": ["action"],
                ],
            ],
            [
                "name": SimWalkTool.mirror.rawValue,
                "description": "Call this instead of screenshotting iPhone Mirroring to drive a real iPhone. 'read' answers the screen; 'tap', 'swipe', 'scroll' and 'menu' act and answer; 'burst' taps, then 1-60 frames. Positions are 0-1 fractions of the mirroring window; the answer's line boxes give them. It never types; a drag does not scroll an app, 'scroll' does. Never tap anything that deletes, signs out or disconnects.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string", "enum": ["read", "tap", "swipe", "scroll", "menu", "burst"], "description": "What to do."],
                        "at": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2, "description": "tap, burst: [x, y] fractions of the window. swipe: where it starts. scroll: the pointer (default [0.5, 0.5])."],
                        "to": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2, "description": "swipe: [x, y] where it ends."],
                        "ms": ["type": "integer", "description": "swipe: how long the drag takes, 50-5000 (default 350)."],
                        "lines": ["type": "integer", "description": "scroll: wheel lines, 1-50; positive reveals what is below (or right), negative above."],
                        "horizontal": ["type": "boolean", "description": "scroll: sideways instead of down."],
                        "item": ["type": "string", "enum": ["home", "switcher"], "description": "menu: Home Screen or App Switcher."],
                        "frames": ["type": "integer", "description": "burst: how many frames, 1-60."],
                        "sheet": ["type": "boolean", "description": "burst: also write sheet.png, the frames tiled and labelled by time."],
                        "match": ["type": "string", "description": "read, tap, swipe, scroll, menu: only the text lines that contain this."],
                        "settleMs": ["type": "integer", "description": "read, tap, swipe, scroll, menu: longest wait for the screen to settle, ms (default 3000)."],
                        "out": ["type": "string", "description": "A directory to keep the captures in, unpruned."],
                    ],
                    "required": ["action"],
                ],
            ],
        ]
    }
}
