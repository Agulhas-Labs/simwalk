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
    /// The PNG of the screen a `read` that asked for one took right after the tree it answers with, turned upright when the device is landscape (SimWalk#221); `nil` when none was asked for, or when ``screenshotRefusal`` says why not.
    public let screenshot: Data?
    /// Why a screenshot that was asked for is not in the answer; `nil` when it is, or was not asked for.
    public let screenshotRefusal: String?
    /// What the runner did that the answer's own fields do not say: a `relaunch` that turned the device to match a landscape app says so here (SimWalk#222, #225); `nil` when there is nothing to say, and absent from an older runner's answer.
    public let notes: [String]?

    public init(n: Int, action: LiveSessionRequest.Action?, screen: LiveScreen? = nil, step: LiveSessionStepAnswer? = nil, failure: String? = nil, screenshot: Data? = nil, screenshotRefusal: String? = nil, notes: [String]? = nil) {
        self.n = n
        self.action = action
        self.screen = screen
        self.step = step
        self.failure = failure
        self.screenshot = screenshot
        self.screenshotRefusal = screenshotRefusal
        self.notes = notes
    }
}
