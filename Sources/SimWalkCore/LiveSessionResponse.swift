//
// Copyright © Agulhas Labs
//

import Foundation

/// The runner's answer to one ``LiveSessionRequest``, filed under the request's own number.
///
/// Either the request was served — a `read` carries its ``LiveScreen`` — or it failed, and ``failure`` says why in the runner's words. A failed request does not end the session: the runner goes on to the next number.
public struct LiveSessionResponse: Codable, Equatable, Sendable {
    /// The number of the request this answers.
    public let n: Int
    public let action: LiveSessionRequest.Action?
    /// What a `read` read, or the screen a `step` left the app on; `nil` for `end`, a step not taken, and a failure.
    public let screen: LiveScreen?
    /// What a `step` came to; `nil` for every other action and for a failure.
    public let step: LiveSessionStepAnswer?
    /// Why the request could not be served; `nil` when it was.
    public let failure: String?

    public init(n: Int, action: LiveSessionRequest.Action?, screen: LiveScreen? = nil, step: LiveSessionStepAnswer? = nil, failure: String? = nil) {
        self.n = n
        self.action = action
        self.screen = screen
        self.step = step
        self.failure = failure
    }
}
