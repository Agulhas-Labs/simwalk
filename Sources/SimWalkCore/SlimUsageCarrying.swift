//
// Copyright © Agulhas Labs
//

import Foundation

/// An error that carries the slim or stock decision its walk took, so the usage log records it on the failed call's line.
///
/// Both faces read it where they record a thrown error: the CLI's `TimedCall` and the MCP server.
public protocol SlimUsageCarrying {
    var slimUsage: SlimUsage? { get }
}
