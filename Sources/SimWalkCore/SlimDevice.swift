//
// Copyright © Agulhas Labs
//

/// A device that booted slim — launchd services switched off by an override file — as the host hands it to the XCUITest runner and the runner reads it back.
///
/// The host writes ``hostEnvironmentKey`` (with the `TEST_RUNNER_` prefix `xcodebuild` strips) and the runner reads it through ``read(in:)``. Both ends name the key and the encoding here, in the package the runner links, so a typo on either side fails a test in `swift test` rather than quietly dropping the clause from a refusal.
public struct SlimDevice: Equatable, Sendable {
    /// The runner-side variable: how many services were off and which capabilities they serve, as ``environmentValue``.
    public static var runnerKey: String {
        "SIMWALK_SLIM_DEVICE"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``runnerKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + runnerKey
    }

    /// How many launchd services were off.
    public let servicesOff: Int
    /// The capabilities, sorted, whose services were among those off.
    public let capabilities: [String]

    public init(servicesOff: Int, capabilities: [String]) {
        self.servicesOff = servicesOff
        self.capabilities = capabilities.sorted()
    }

    /// The count, then `;`, then the capabilities joined by `,` — `94;healthKit,location`.
    public var environmentValue: String {
        "\(servicesOff);" + capabilities.joined(separator: ",")
    }

    /// The device the runner's `environment` names, or `nil` where the key is missing or malformed (no count above zero, or a capability that is empty).
    public static func read(in environment: [String: String]) -> SlimDevice? {
        guard let raw = environment[runnerKey] else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let count = Int(parts[0]), count > 0 else { return nil }
        let names = parts[1].isEmpty ? [] : parts[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !names.contains(where: \.isEmpty) else { return nil }
        return SlimDevice(servicesOff: count, capabilities: names)
    }

    /// What a refusal that saw no sheet appends: how many launchd services the device has set off, which capabilities they serve, and how to walk stock.
    public var clause: String {
        let among = capabilities.isEmpty ? "" : ", among them those serving " + capabilities.joined(separator: ", ")
        return "; the device has \(servicesOff) launchd services set off\(among) — a sheet whose service is off never appears: walk again with --stock to rule that out"
    }
}
