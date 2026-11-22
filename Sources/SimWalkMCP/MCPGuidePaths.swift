//
// Copyright © Agulhas Labs
//

import Foundation

/// Where the agent guide and `Docs/Reference.md` are on this machine, each only when its file is readable.
public struct MCPGuidePaths: Equatable, Sendable {
    var guide: String?
    var reference: String?

    public init(guide: String? = nil, reference: String? = nil) {
        self.guide = guide
        self.reference = reference
    }

    /// The installed rule is the guide; `Docs/Reference.md` is the first readable of the one beside a packaged binary (`shippedDirectory`) and the one in the checkout a development build was compiled from.
    public static func resolve(rule: URL, shippedDirectory: URL?, checkout: URL?, isReadable: (String) -> Bool) -> MCPGuidePaths {
        let references = [shippedDirectory, checkout].compactMap { $0?.appendingPathComponent("Docs/Reference.md").path }
        return MCPGuidePaths(
            guide: isReadable(rule.path) ? rule.path : nil,
            reference: references.first(where: isReadable)
        )
    }
}
