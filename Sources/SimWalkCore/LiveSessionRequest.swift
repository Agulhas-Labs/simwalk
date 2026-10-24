//
// Copyright © Agulhas Labs
//

import Foundation

/// One request to a live session's runner: `{"n": 1, "action": "read"}`, or `{"n": 2, "action": "step", "step": {"tap": {"label": "Next"}}, "guard": "1a2b3c4d"}`.
///
/// **`n` is the request's place in the session**, the same number its file and its response's file carry, and the runner serves them strictly in that order. It is inside the file as well as in the name so a response can be checked against the request it claims to answer. Further actions arrive as new cases of ``Action`` and new optional fields beside it, so a runner that meets one it does not know answers a failure rather than guessing.
public struct LiveSessionRequest: Codable, Equatable, Sendable {
    public let n: Int
    public let action: Action
    /// The route step a `step` request takes, in walkbook form; `nil` for every other action.
    public let step: Walkbook.RouteStep?
    /// The ``ScreenHash`` the screen must still have for the step to be taken — the one the caller last read; `nil` to take the step unguarded.
    public let guardHash: String?
    /// The drag a `scroll` request makes; `nil` for every other action.
    public let scroll: LiveSessionScroll?
    /// Whether a `read` also answers with a PNG of the app, taken right after the tree it answers with; ignored by every other action.
    public let screenshot: Bool

    public init(n: Int, action: Action, step: Walkbook.RouteStep? = nil, guardHash: String? = nil, scroll: LiveSessionScroll? = nil, screenshot: Bool = false) {
        self.n = n
        self.action = action
        self.step = step
        self.guardHash = guardHash
        self.scroll = scroll
        self.screenshot = screenshot
    }
}

public extension LiveSessionRequest {
    /// `guard` on the wire, which is a keyword in Swift.
    internal enum CodingKeys: String, CodingKey {
        case n
        case action
        case step
        case guardHash = "guard"
        case scroll
        case screenshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = try container.decode(Int.self, forKey: .n)
        action = try container.decode(Action.self, forKey: .action)
        step = try container.decodeIfPresent(Walkbook.RouteStep.self, forKey: .step)
        guardHash = try container.decodeIfPresent(String.self, forKey: .guardHash)
        scroll = try container.decodeIfPresent(LiveSessionScroll.self, forKey: .scroll)
        screenshot = try container.decodeIfPresent(Bool.self, forKey: .screenshot) ?? false
    }

    /// Writes `screenshot` only when true, so every request that does not ask for one is byte-identical to what it was before the key existed.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(n, forKey: .n)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(guardHash, forKey: .guardHash)
        try container.encodeIfPresent(scroll, forKey: .scroll)
        if screenshot {
            try container.encode(true, forKey: .screenshot)
        }
    }
}

public extension LiveSessionRequest {
    /// What the runner is asked to do.
    enum Action: String, Codable, Equatable, Sendable {
        /// Read the app as it stands — the same ``LiveScreen`` `simwalk inspect` reads.
        case read
        /// Take one route step, exactly as a walk takes it, and read the screen it landed on.
        case step
        /// End the app and launch it again exactly as the session launched it — same state, arguments, environment and appearance — and read the screen it settles on: how `discover` gets back to a screen it has no back button to.
        case relaunch
        /// Drag a scroll container once, settle as after a step, and answer the screen it left.
        ///
        /// How `discover` reads below the fold; only `discover` sends it.
        case scroll
        /// Stop serving: the runner answers, writes its exit record, and returns, which ends the `xcodebuild` run.
        case end
    }
}
