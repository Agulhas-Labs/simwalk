//
// Copyright © Agulhas Labs
//

import Foundation

/// What `walk_status` answers: the text and whether it is a refusal.
public struct WalkStatus: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}
