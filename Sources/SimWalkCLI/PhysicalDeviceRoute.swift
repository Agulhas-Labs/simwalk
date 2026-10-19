//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkDriver

/// What a `--device` or `--lease` names when it is a physical iPhone or iPad rather than a simulator (SimWalk#116): read by `walk` and `session start` before either path touches a device.
enum PhysicalDeviceRoute: Equatable {
    /// A lease on a physical device, which names the device.
    case leased
    /// A UDID `simctl` does not list and `devicectl list devices` reports as a physical device.
    case udid(String)

    /// The UDID named, `nil` when the lease names the device.
    var udid: String? {
        guard case let .udid(udid) = self else { return nil }
        return udid
    }

    /// The physical device named, or `nil` for the simulator path.
    ///
    /// A `--lease` whose lease is on a physical device, or a `--device` that `simctl` lists no simulator for (by UDID or name) and `devicectl list devices` reports as physical, is a physical device. Both are reads. A `--device` known to neither is left to the simulator path's own refusal, with the physical UDIDs present added when there are any; a `devicectl` that cannot be read changes nothing, as a machine without a phone has none to name.
    ///
    /// The `simctl list` is the command's first `simctl` call on this path, so `firstLaunch` is asked first (SimWalk#136); a lease names its device without one, and asks nothing.
    static func resolve(device: String?, lease: String?, shell: Shell, leases: LeaseStore, firstLaunch: XcodeFirstLaunch.Check) throws -> PhysicalDeviceRoute? {
        if let lease {
            return leases.entry(token: lease)?.lease.physicalDevice == true ? .leased : nil
        }
        guard let device else { return nil }
        try firstLaunch.preflight(shell: shell)
        let simulators = try Simulator.available(shell: shell)
        guard !simulators.contains(where: { $0.udid == device || $0.name == device }) else { return nil }
        do {
            _ = try PhysicalDevicePrerequisites.listed(udid: device, shell: shell)
            return .udid(device)
        } catch let PhysicalDeviceError.notFound(_, present) where !present.isEmpty {
            throw DeviceWalkRefusal.unknownDevice(requested: device, simulators: simulators.map(\.name), physical: present)
        } catch {
            return nil
        }
    }
}
