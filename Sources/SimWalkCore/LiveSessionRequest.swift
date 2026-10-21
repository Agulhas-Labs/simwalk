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

    public init(n: Int, action: Action, step: Walkbook.RouteStep? = nil, guardHash: String? = nil) {
        self.n = n
        self.action = action
        self.step = step
        self.guardHash = guardHash
    }
}

extension LiveSessionRequest {
    /// `guard` on the wire, which is a keyword in Swift.
    enum CodingKeys: String, CodingKey {
        case n
        case action
        case step
        case guardHash = "guard"
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
        /// Stop serving: the runner answers, writes its exit record, and returns, which ends the `xcodebuild` run.
        case end
    }
}
