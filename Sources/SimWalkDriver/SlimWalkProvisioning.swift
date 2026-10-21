//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// What a walk does to a device's launchd services around its boot: the override written or removed before, and the read-back after.
///
/// **Only a device SimWalk created is ever touched.** The override file is keyed by UDID and outlives `simctl erase`, so a device somebody else made would keep a slim set nobody told its owner about. `createdByWalk` is the lease's own record that the device is a clone made for a lease.
public struct SlimWalkProvisioning {
    private let shell: Shell
    /// Where this provisioning writes and removes each device's override: the machine's own, or a test's scratch root.
    public let overrides: DisabledServicesOverride
    private let profileLookup: (String) -> ServiceProfile?

    public init(
        shell: Shell,
        overrides: DisabledServicesOverride = DisabledServicesOverride(),
        profileLookup: @escaping (String) -> ServiceProfile? = ServiceProfiles.profile(forRuntime:)
    ) {
        self.shell = shell
        self.overrides = overrides
        self.profileLookup = profileLookup
    }

    /// Settles the override, boots the device through `boot`, and returns the line the answer carries (``afterBoot(_:)``).
    ///
    /// The override is in place before `boot` runs because `launchd_sim` reads it only as the device starts; `boot` is handed the device shut down when this had to shut it down.
    public func boot(_ simulator: Simulator, createdByWalk: Bool, stockRequested: Bool, appPath: String?, boot: (Simulator) throws -> Void) throws -> String? {
        let provisioned = try beforeBoot(simulator, createdByWalk: createdByWalk, stockRequested: stockRequested, appPath: appPath)
        try boot(provisioned.simulator)
        return afterBoot(provisioned)
    }

    /// Settles the device's override before the walk boots it.
    ///
    /// - A shut-down device of the walk's: with `appPath`, slim or stock as ``WalkBootMode/decide(stockRequested:runtimeIdentifier:osVersion:profileLookup:declarations:)`` says, the override rewritten from nothing so an earlier app's kept services do not linger; with `--stock` alone, the override removed; otherwise left as it is.
    /// - A booted device of the walk's under `--stock` that has an override: shut down, the override removed, and returned shut down so the boot that follows boots it.
    /// - Any other device: nothing is changed, and `--stock` on one that has an override is refused.
    public func beforeBoot(_ simulator: Simulator, createdByWalk: Bool, stockRequested: Bool, appPath: String?) throws -> Provisioned {
        guard createdByWalk else {
            guard stockRequested else { return Provisioned(simulator: simulator, decision: nil) }
            let off = try disabledLabels(for: simulator.udid, createdByWalk: false).count
            if off > 0 {
                throw SlimWalkError.stockOnForeignDevice(udid: simulator.udid, off: off)
            }
            return Provisioned(simulator: simulator, decision: nil)
        }
        if simulator.isBooted {
            guard stockRequested, try !disabledLabels(for: simulator.udid, createdByWalk: true).isEmpty else { return Provisioned(simulator: simulator, decision: nil) }
            try shutDown(simulator.udid)
            try overrides.remove(for: simulator.udid)
            let down = Simulator(udid: simulator.udid, name: simulator.name, osVersion: simulator.osVersion, isBooted: false, runtimeIdentifier: simulator.runtimeIdentifier)
            return Provisioned(simulator: down, decision: .stock(.requested))
        }
        guard let appPath else {
            guard stockRequested else { return Provisioned(simulator: simulator, decision: nil) }
            try overrides.remove(for: simulator.udid)
            return Provisioned(simulator: simulator, decision: .stock(.requested))
        }
        let decision = WalkBootMode.decide(
            stockRequested: stockRequested,
            runtimeIdentifier: simulator.runtimeIdentifier ?? "",
            osVersion: simulator.osVersion,
            profileLookup: profileLookup,
            declarations: { AppDeclarations.read(appPath: appPath) }
        )
        try overrides.remove(for: simulator.udid)
        if case let .slim(boot) = decision {
            try overrides.write(boot.plan.disabled, for: simulator.udid)
        }
        return Provisioned(simulator: simulator, decision: decision)
    }

    /// The line the walk's answer carries about the device, after the boot; `nil` when nothing was decided.
    ///
    /// A slim decision is read back from the booted device. A problem reading it back never fails the walk: it is said in the line.
    public func afterBoot(_ provisioned: Provisioned) -> String? {
        guard let decision = provisioned.decision else { return nil }
        guard case let .slim(boot) = decision else { return "device: \(decision.text)" }
        let planned = Set(boot.plan.disabled)
        let read: Shell.Result
        do {
            read = try shell.run("/usr/bin/xcrun", ["simctl", "spawn", provisioned.simulator.udid, "launchctl", "print-disabled", "system"], timeout: 20)
        } catch ShellError.timedOut {
            return "device: slim, unverified: the read-back timed out"
        } catch {
            return "device: slim, unverified: the read-back failed: \(error)"
        }
        guard read.succeeded else { return "device: slim, unverified: the read-back failed: \(read.failureLine)" }
        let applied = planned.intersection(DisabledServicesOverride.disabledLabels(fromPrintDisabled: read.standardOutput))
        guard applied.count == planned.count else {
            return "device: not slim: the runtime did not apply the override (\(applied.count) of \(planned.count) read back)"
        }
        return "device: \(decision.text)"
    }

    /// The labels the device's override switches off; a file that is there and cannot be read is ``SlimWalkError/overrideUnreadable(path:reason:createdByWalk:)``, a missing one is none.
    private func disabledLabels(for udid: String, createdByWalk: Bool) throws -> Set<String> {
        let path = try overrides.directory(for: udid).appendingPathComponent("disabled.plist").path
        do {
            return try overrides.labels(for: udid)
        } catch {
            throw SlimWalkError.overrideUnreadable(path: path, reason: error.localizedDescription, createdByWalk: createdByWalk)
        }
    }

    private func shutDown(_ udid: String) throws {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "shutdown", udid])
        guard result.succeeded || result.failureLine.contains("current state: Shutdown") else {
            throw SimulatorError.simctlFailed(command: "shutdown", reason: result.failureLine)
        }
    }
}

public extension SlimWalkProvisioning {
    /// The device to boot and what was decided for it; `decision` is `nil` when nothing was decided.
    struct Provisioned: Equatable {
        public let simulator: Simulator
        public let decision: WalkBootMode?
    }
}
