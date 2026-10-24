//
// Copyright © Agulhas Labs
//

import Foundation

/// One drag of a scroll container, as a `scroll` request carries it: which way, and the container's box as the caller last read it.
public struct LiveSessionScroll: Codable, Equatable, Sendable {
    public let direction: Direction
    public let container: AXNode.Frame

    public init(direction: Direction, container: AXNode.Frame) {
        self.direction = direction
        self.container = container
    }
}

public extension LiveSessionScroll {
    /// Which way the list moves.
    enum Direction: String, Codable, Equatable, Sendable {
        /// Towards the list's end: the content moves up.
        case down
        /// Back towards the list's start.
        case up
    }
}
