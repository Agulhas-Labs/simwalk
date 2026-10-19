//
// Copyright © Agulhas Labs
//

/// `SIMWALK_MCP_CALL_BUDGET`: the longest a bounded call waits, in seconds.
struct MCPCallBudget: Equatable {
    static var environmentKey: String {
        "SIMWALK_MCP_CALL_BUDGET"
    }

    static let defaultSeconds = 50.0

    let seconds: Double
    /// The stderr line for an unusable value, `nil` when the value was usable or unset.
    let warning: String?

    /// Fractions are accepted; a value that is unparsable or not positive falls back to the default.
    init(environment: [String: String]) {
        guard let raw = environment[Self.environmentKey] else {
            seconds = Self.defaultSeconds
            warning = nil
            return
        }
        if let value = Double(raw.trimmed), value.isFinite, value > 0 {
            seconds = value
            warning = nil
        } else {
            seconds = Self.defaultSeconds
            warning = "simwalk mcp: \(Self.environmentKey) '\(raw)' is not a positive number of seconds; using \(Int(Self.defaultSeconds))"
        }
    }
}
