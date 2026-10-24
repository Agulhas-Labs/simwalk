//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Reads an installed app's `UIDeviceFamily` and refuses what cannot run natively on a simulator (SimWalk#166).
///
/// A physical iPad is not checked yet: this reads a simulator's installed bundle only.
public struct AppDeviceFamilies {
    /// The bundle's `UIDeviceFamily`, nil when `Info.plist` is missing, unreadable or holds neither an array of whole numbers nor a single one (an older bundle's form, SimWalk#166 review).
    public static func read(appAt path: String) -> [Int]? {
        let url = URL(fileURLWithPath: path).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        if let families = plist["UIDeviceFamily"] as? [Int] {
            return families
        }
        return (plist["UIDeviceFamily"] as? Int).map { [$0] }
    }

    /// Throws when the app installed at `path` is iPhone-only and `simulator` is an iPad.
    public static func require(bundleID: String, installedAt path: String, on simulator: Simulator) throws {
        try require(bundleID: bundleID, appAt: path, on: simulator)
    }

    /// Throws when the `.app` at `path` is iPhone-only and `simulator` is an iPad: the same refusal, asked of a bundle not yet installed so a `--app-path` is refused before the device is booted or the app installed (SimWalk#219).
    ///
    /// The device type comes from `simctl list`, so a shut-down device answers.
    public static func require(bundleID: String, appAt path: String, on simulator: Simulator) throws {
        if let refusal = DeviceFamilyCheck.refusal(
            bundleID: bundleID,
            families: read(appAt: path),
            deviceTypeIdentifier: simulator.deviceTypeIdentifier,
            deviceName: simulator.name,
            udid: simulator.udid
        ) {
            throw SimulatorError.iPhoneOnlyAppOnIPad(refusal)
        }
    }
}
