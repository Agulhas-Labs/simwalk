//
// Copyright © Agulhas Labs
//

import Foundation

/// A request as the host sends it to a device's runner: a ``LiveSessionRequest`` without its number.
///
/// **The runner numbers a device's requests** (Brief, "Live sessions on a physical device", ruling 4). On a simulator the host claims a number with the rename that also sends it; over a socket the claim and the send would be two steps, and a host that died between them would leave a number the runner waits on for ever. So the request travels unnumbered, the runner serves it as `served + 1`, and its response carries that number back to be filed under.
public struct DeviceSessionRequest: Codable, Equatable, Sendable {
    public let action: LiveSessionRequest.Action
    /// The route step a `step` request takes, in walkbook form; `nil` for every other action.
    public let step: Walkbook.RouteStep?
    /// The ``ScreenHash`` the screen must still have for the step to be taken; `nil` to take the step unguarded.
    public let guardHash: String?

    public init(action: LiveSessionRequest.Action, step: Walkbook.RouteStep? = nil, guardHash: String? = nil) {
        self.action = action
        self.step = step
        self.guardHash = guardHash
    }

    /// This request under the number the runner gave it.
    public func numbered(_ number: Int) -> LiveSessionRequest {
        LiveSessionRequest(n: number, action: action, step: step, guardHash: guardHash)
    }
}

extension DeviceSessionRequest {
    /// `guard` on the wire, as ``LiveSessionRequest`` writes it.
    enum CodingKeys: String, CodingKey {
        case action
        case step
        case guardHash = "guard"
    }
}
