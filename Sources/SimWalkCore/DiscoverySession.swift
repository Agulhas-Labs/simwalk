//
// Copyright © Agulhas Labs
//

import Foundation

/// What `discover` needs of a running app: read the screen, send one route step, and start the app over from its launch state.
///
/// **The crawl's only way into the app**, so `DiscoverCrawl` can be replayed against a scripted app in a test and driven by a resident session on a device. A live implementation sends each step as `session step` does and relaunches the way `session start` launched.
public protocol DiscoverySession {
    /// The screen the app is on now.
    func read() throws -> LiveScreen

    /// Sends one step and returns the runner's response: what the step came to (`step`) and the screen it left the app on (`screen`).
    func send(_ step: Walkbook.RouteStep) throws -> LiveSessionResponse

    /// Ends the app and launches it again in the session's capture state, returning the launch screen.
    func relaunch() throws -> LiveScreen
}
