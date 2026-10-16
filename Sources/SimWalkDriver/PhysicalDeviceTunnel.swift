//
// Copyright © Agulhas Labs
//

import Foundation

/// The CoreDevice tunnel to a physical device as `devicectl list devices` reports it: the device's own end of it, where a live session's runner listens (Brief, "Live sessions on a physical device", ruling 1).
///
/// **An address is good for the life of the tunnel only**: every new tunnel has a new one, and with nothing holding it the tunnel drops about 10 s after a device call. So it is read again on every turn of `start`'s ready loop, and once after a failed connect.
public struct PhysicalDeviceTunnel: Equatable, Sendable {
    /// The device's end of the tunnel; `nil` when there is no tunnel up.
    public let address: String?
    /// `connectionProperties.tunnelState`, e.g. `connected`, `disconnected`; `nil` when not reported.
    public let state: String?

    public init(address: String?, state: String?) {
        self.address = address
        self.state = state
    }

    /// The tunnel to `udid` in `listDevicesJSON`; no address when the device is absent or its tunnel is not up.
    ///
    /// `properties.connection.tunnelIPAddressString` first, the dictionary devicectl names as the replacement, then the deprecated `connectionProperties.tunnelIPAddress`, which is also the only one carrying `tunnelState`. A state reported other than `connected` is no tunnel, whatever address is beside it.
    public static func parse(listDevicesJSON: Data, udid: String) -> PhysicalDeviceTunnel {
        guard let root = try? JSONSerialization.jsonObject(with: listDevicesJSON) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]],
              let device = devices.first(where: { (($0["properties"] as? [String: Any])?["hardware"] as? [String: Any])?["udid"] as? String == udid })
        else {
            return PhysicalDeviceTunnel(address: nil, state: nil)
        }
        let connection = (device["properties"] as? [String: Any])?["connection"] as? [String: Any] ?? [:]
        let deprecated = device["connectionProperties"] as? [String: Any] ?? [:]
        let state = deprecated["tunnelState"] as? String
        let address = connection["tunnelIPAddressString"] as? String ?? deprecated["tunnelIPAddress"] as? String
        guard state == nil || state == "connected", let address, !address.isEmpty else {
            return PhysicalDeviceTunnel(address: nil, state: state)
        }
        return PhysicalDeviceTunnel(address: address, state: state)
    }

    /// Runs `devicectl list devices` and reads `udid`'s tunnel; no address when the listing could not be read.
    public static func read(udid: String, shell: Shell) -> PhysicalDeviceTunnel {
        guard let listing = try? PhysicalDevicePrerequisites.devicectl(["list", "devices"], command: PhysicalDevice.command, shell: shell) else {
            return PhysicalDeviceTunnel(address: nil, state: nil)
        }
        return parse(listDevicesJSON: listing, udid: udid)
    }
}
