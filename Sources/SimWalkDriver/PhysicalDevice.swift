//
// Copyright © Agulhas Labs
//

import Foundation

/// A physical iPhone as `xcrun devicectl list devices` reports it (SimWalk#116).
///
/// Read from each device's `properties` dictionary only: `hardwareProperties`, `deviceProperties` and `connectionProperties` carry a `_deprecationNotice` saying they will be removed.
public struct PhysicalDevice: Equatable, Sendable {
    public let udid: String
    public let name: String
    public let marketingName: String
    public let productType: String
    public let osVersion: String
    /// How the Mac reaches it, e.g. `wired` or `localNetwork`.
    public let transportType: String
    public let pairingState: String
    /// `properties.connection.state`, e.g. `connected`.
    public let connectionState: String
    /// `nil` when `devicectl` did not say — unreadable, never assumed enabled.
    public let developerModeEnabled: Bool?
    /// What `devicectl` reported for Developer Mode, for a refusal to quote; `nil` when the key was missing.
    public let developerModeReport: String?

    static var command: String {
        "devicectl list devices"
    }

    /// What a display field reads as when `devicectl` did not report it: an offline or untrusted phone often omits them, and they must not stop the pairing and connection checks from naming the real reason.
    static var unknown: String {
        #function
    }

    /// The physical device with `udid` in `listDevicesJSON`.
    ///
    /// Developer Mode is enabled only when `properties.state.developerModeStatus` is an object holding the key `enabled` (observed: `{"enabled": {"mode": 1}}`); any other shape is not enabled.
    public static func parse(listDevicesJSON: Data, udid: String) throws -> PhysicalDevice {
        func unreadable(_ reason: String) -> PhysicalDeviceError {
            .unreadable(command: command, reason: reason)
        }
        guard let root = try? JSONSerialization.jsonObject(with: listDevicesJSON) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]]
        else {
            throw unreadable("the output is not a devicectl device list")
        }
        let physical = devices.compactMap { device -> (udid: String, properties: [String: Any])? in
            guard let properties = device["properties"] as? [String: Any],
                  let hardware = properties["hardware"] as? [String: Any],
                  hardware["reality"] as? String == "physical",
                  let id = hardware["udid"] as? String
            else { return nil }
            return (id, properties)
        }
        guard let match = physical.first(where: { $0.udid == udid }) else {
            throw PhysicalDeviceError.notFound(udid: udid, present: physical.map(\.udid))
        }
        let properties = match.properties
        let hardware = properties["hardware"] as? [String: Any] ?? [:]
        let connection = properties["connection"] as? [String: Any] ?? [:]
        let state = properties["state"] as? [String: Any] ?? [:]
        let software = properties["software"] as? [String: Any] ?? [:]
        let osVersion = (software["osVersionNumber"] as? [String: Any])?["stringValue"] as? String

        func required(_ value: String?, _ path: String) throws -> String {
            guard let value else { throw unreadable("\(path) is missing for \(udid)") }
            return value
        }
        let status = state["developerModeStatus"]
        return try PhysicalDevice(
            udid: udid,
            name: state["name"] as? String ?? Self.unknown,
            marketingName: hardware["marketingName"] as? String ?? Self.unknown,
            productType: required(hardware["productType"] as? String, "properties.hardware.productType"),
            osVersion: osVersion ?? Self.unknown,
            transportType: connection["transportType"] as? String ?? Self.unknown,
            pairingState: required(connection["pairingState"] as? String, "properties.connection.pairingState"),
            connectionState: required(connection["state"] as? String, "properties.connection.state"),
            developerModeEnabled: status.map { ($0 as? [String: Any])?["enabled"] != nil },
            developerModeReport: status.flatMap { value in
                JSONSerialization.isValidJSONObject(value)
                    ? (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) }
                    : "\"\(value)\""
            }
        )
    }
}
