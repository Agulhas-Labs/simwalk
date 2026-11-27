//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices
import SimWalkCore

/// What a walk does to a device's launchd services around its boot: the override written, put back or removed before, and the read-back after.
///
/// **A device SimWalk did not create is slimmed only on request** (`slimRequested`, the walk's `--slim`). The override file is keyed by UDID and outlives `simctl erase`, so a device somebody else made would keep a slim set nobody told its owner about unless its owner asked. `createdByWalk` is the lease's own record that the device is a clone made for a lease. `launchd_sim` reads the override only at boot, so a booted device is shut down for a change only when the walk may reboot it (`mayReboot`, ``DeviceSettle/mayReboot(_:requested:leased:)``), and the walk refuses otherwise.
///
/// Undoing is exact on a device SimWalk did not create: `--stock` puts back what the walk's writes switched off (``DisabledServicesOverride/restore(for:)``), so an entry someone else put there stays. A device SimWalk created has its override directory removed (``DisabledServicesOverride/remove(for:)``), since everything in it is SimWalk's.
public struct SlimWalkProvisioning {
    private let shell: Shell
    /// Where this provisioning writes and removes each device's override: the machine's own, or a test's scratch root.
    public let overrides: DisabledServicesOverride
    private let resolve: (String) -> ProfileResolution

    public init(
        shell: Shell,
        overrides: DisabledServicesOverride = DisabledServicesOverride(),
        resolve: @escaping (String) -> ProfileResolution = { ServiceProfiles.resolve(forRuntime: $0) }
    ) {
        self.shell = shell
        self.overrides = overrides
        self.resolve = resolve
    }

    /// Settles the override, boots the device through `boot`, and returns the line the answer carries (``afterBoot(_:)``).
    ///
    /// The override is in place before `boot` runs because `launchd_sim` reads it only as the device starts; `boot` is handed the device shut down when this had to shut it down.
    public func boot(
        _ simulator: Simulator,
        createdByWalk: Bool,
        slimRequested: Bool = false,
        stockRequested: Bool,
        mayReboot: Bool,
        appPath: String?,
        boot: (Simulator) throws -> Void
    ) throws -> String? {
        try bootNoting(simulator, createdByWalk: createdByWalk, slimRequested: slimRequested, stockRequested: stockRequested, mayReboot: mayReboot, appPath: appPath, boot: boot)?.line
    }

    /// ``boot(_:createdByWalk:slimRequested:stockRequested:mayReboot:appPath:boot:)`` returning the verdict beside the line.
    public func bootNoting(
        _ simulator: Simulator,
        createdByWalk: Bool,
        slimRequested: Bool = false,
        stockRequested: Bool,
        mayReboot: Bool,
        appPath: String?,
        boot: (Simulator) throws -> Void
    ) throws -> DeviceNote? {
        let provisioned = try beforeBoot(simulator, createdByWalk: createdByWalk, slimRequested: slimRequested, stockRequested: stockRequested, mayReboot: mayReboot, appPath: appPath)
        try boot(provisioned.simulator)
        return deviceNote(after: provisioned)
    }

    /// Settles the device's override before the walk boots it.
    ///
    /// - `--stock`: with labels a slim walk switched off (on a device SimWalk created, any label in its override; on another, ``DisabledServicesOverride/ownedLabels(for:)``), they are put back, a booted device shut down first and returned shut down so the boot that follows boots it, or ``SlimWalkError/bootedInUse(udid:switchingOff:)`` when `mayReboot` is false. With none, nothing is touched and the decision is ``WalkStockReason/nothingToPutBack``.
    /// - A shut-down device SimWalk created or was asked to slim, with `appPath`: slim or stock as ``WalkBootMode/decide(stockRequested:runtimeIdentifier:osVersion:resolve:declarations:)`` says, the override rewritten from what it held before the walk's earlier writes so an earlier app's kept services do not linger.
    /// - A booted device under `--slim` with `appPath`: shut down and then as a shut-down one when the decision is slim, or when it is stock and the walk's earlier writes switched labels off there (counted as `--stock` counts them), which are put back so the boot that follows boots it stock; refused with ``SlimWalkError/bootedInUse(udid:switchingOff:)`` instead of either when not `mayReboot`. A stock decision with nothing to put back is said and nothing is touched.
    /// - Every refusal comes before every side effect: a booted device's override is read, as far as settling it will read it, before the device is shut down, so an override that cannot be read (``SlimWalkError/overrideUnreadable(path:reason:createdByWalk:)``) leaves the device booted and its files as they were.
    /// - Any other device, including a booted one SimWalk created without `--slim`: nothing is changed and nothing decided.
    public func beforeBoot(_ simulator: Simulator, createdByWalk: Bool, slimRequested: Bool = false, stockRequested: Bool, mayReboot: Bool, appPath: String?) throws -> Provisioned {
        if stockRequested {
            return try stock(simulator, createdByWalk: createdByWalk, mayReboot: mayReboot)
        }
        guard createdByWalk || slimRequested, let appPath, !simulator.isBooted || slimRequested else {
            return Provisioned(simulator: simulator, decision: nil)
        }
        let decision = WalkBootMode.decide(
            stockRequested: false,
            runtimeIdentifier: simulator.runtimeIdentifier ?? "",
            osVersion: simulator.osVersion,
            resolve: resolve,
            declarations: { AppDeclarations.read(appPath: appPath) }
        )
        var device = simulator
        if simulator.isBooted {
            if case .slim = decision {
                try checkReadable(simulator.udid, createdByWalk: createdByWalk)
                device = try shutDown(simulator, mayReboot: mayReboot, switchingOff: true)
            } else {
                // A stock decision on a device an earlier walk slimmed is a change too: left alone, the earlier switch-off would stay live under a line that says stock.
                guard try !earlierWrites(simulator.udid, createdByWalk: createdByWalk).isEmpty else {
                    return Provisioned(simulator: simulator, decision: decision)
                }
                try checkReadable(simulator.udid, createdByWalk: createdByWalk)
                device = try shutDown(simulator, mayReboot: mayReboot, switchingOff: false)
            }
        }
        try settle(simulator.udid, createdByWalk: createdByWalk) {
            try clear(simulator.udid, createdByWalk: createdByWalk)
            if case let .slim(boot) = decision {
                try overrides.write(boot.plan.disabled, for: simulator.udid)
            }
        }
        return Provisioned(simulator: device, decision: decision)
    }

    /// The line the walk's answer carries about the device, after the boot; `nil` when nothing was decided.
    ///
    /// A slim decision is read back from the booted device. A problem reading it back never fails the walk: it is said in the line.
    public func afterBoot(_ provisioned: Provisioned) -> String? {
        deviceNote(after: provisioned)?.line
    }

    /// ``afterBoot(_:)`` with the verdict its line states, for the usage log: the same branches choose both.
    public func deviceNote(after provisioned: Provisioned) -> DeviceNote? {
        guard let decision = provisioned.decision else { return nil }
        guard case let .slim(boot) = decision else { return DeviceNote(line: "device: \(decision.text)", verdict: .stock) }
        let planned = Set(boot.plan.disabled)
        let read: Shell.Result
        do {
            read = try shell.run("/usr/bin/xcrun", ["simctl", "spawn", provisioned.simulator.udid, "launchctl", "print-disabled", "system"], timeout: 20)
        } catch ShellError.timedOut {
            return DeviceNote(line: "device: slim, unverified: the read-back timed out", verdict: .slimUnverified)
        } catch {
            return DeviceNote(line: "device: slim, unverified: the read-back failed: \(error)", verdict: .slimUnverified)
        }
        guard read.succeeded else { return DeviceNote(line: "device: slim, unverified: the read-back failed: \(read.failureLine)", verdict: .slimUnverified) }
        let applied = planned.intersection(DisabledServicesOverride.disabledLabels(fromPrintDisabled: read.standardOutput))
        guard applied.count == planned.count else {
            return DeviceNote(line: "device: not slim: the runtime did not apply the override (\(applied.count) of \(planned.count) read back)", verdict: .notSlim)
        }
        return DeviceNote(line: "device: \(decision.text)", verdict: .slim)
    }

    /// `--stock`: what a slim walk switched off is put back, or nothing is touched when it switched nothing off.
    private func stock(_ simulator: Simulator, createdByWalk: Bool, mayReboot: Bool) throws -> Provisioned {
        guard try !earlierWrites(simulator.udid, createdByWalk: createdByWalk).isEmpty else {
            return Provisioned(simulator: simulator, decision: .stock(.nothingToPutBack))
        }
        try checkReadable(simulator.udid, createdByWalk: createdByWalk)
        let device = simulator.isBooted ? try shutDown(simulator, mayReboot: mayReboot, switchingOff: false) : simulator
        try settle(simulator.udid, createdByWalk: createdByWalk) { try clear(simulator.udid, createdByWalk: createdByWalk) }
        return Provisioned(simulator: device, decision: .stock(.requested))
    }

    /// The labels the walk's earlier writes switched off: on a device SimWalk created, any label in its override; on another, ``DisabledServicesOverride/ownedLabels(for:)``.
    private func earlierWrites(_ udid: String, createdByWalk: Bool) throws -> Set<String> {
        try settle(udid, createdByWalk: createdByWalk) {
            try createdByWalk ? overrides.labels(for: udid) : overrides.ownedLabels(for: udid)
        }
    }

    /// Makes now every read that ``clear(_:createdByWalk:)`` and the write after it will make, so an override that cannot be read is refused before the device is shut down: putting the walk's labels back on a device SimWalk did not create reads both the override file and the walk's record of it, and removing a created device's directory reads nothing.
    private func checkReadable(_ udid: String, createdByWalk: Bool) throws {
        guard !createdByWalk else { return }
        try settle(udid, createdByWalk: createdByWalk) {
            _ = try overrides.labels(for: udid)
            _ = try overrides.ownedLabels(for: udid)
        }
    }

    /// Takes back the walk's earlier writes: a device SimWalk created loses its override directory, which is all SimWalk's; another has only the walk's own labels put back.
    private func clear(_ udid: String, createdByWalk: Bool) throws {
        if createdByWalk {
            try overrides.remove(for: udid)
        } else {
            try overrides.restore(for: udid)
        }
    }

    /// Runs `body` on the device's override, turning a file that is there and cannot be read into ``SlimWalkError/overrideUnreadable(path:reason:createdByWalk:)``.
    private func settle<T>(_: String, createdByWalk: Bool, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let SimulatorServicesError.unreadableOverride(path, reason) {
            throw SlimWalkError.overrideUnreadable(path: path, reason: reason, createdByWalk: createdByWalk)
        }
    }

    /// Shuts a booted device down so the override takes effect at the boot that follows, and returns it as shut down; refuses a device the walk may not reboot.
    private func shutDown(_ simulator: Simulator, mayReboot: Bool, switchingOff: Bool) throws -> Simulator {
        guard mayReboot else { throw SlimWalkError.bootedInUse(udid: simulator.udid, switchingOff: switchingOff) }
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "shutdown", simulator.udid])
        guard result.succeeded || result.failureLine.contains("current state: Shutdown") else {
            throw SimulatorError.simctlFailed(command: "shutdown", reason: result.failureLine)
        }
        return Simulator(udid: simulator.udid, name: simulator.name, osVersion: simulator.osVersion, isBooted: false, runtimeIdentifier: simulator.runtimeIdentifier)
    }
}

public extension SlimWalkProvisioning {
    /// The device to boot and what was decided for it; `decision` is `nil` when nothing was decided.
    struct Provisioned: Equatable {
        public let simulator: Simulator
        public let decision: WalkBootMode?
    }
}

public extension SlimWalkProvisioning {
    /// What the walk says about the device after its boot: the answer's `device:` line, and the verdict that line states.
    struct DeviceNote: Equatable, Sendable {
        public let line: String
        public let verdict: SlimUsage.Verdict

        public init(line: String, verdict: SlimUsage.Verdict) {
            self.line = line
            self.verdict = verdict
        }
    }
}
