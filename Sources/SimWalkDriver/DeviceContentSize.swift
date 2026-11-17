//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The Dynamic Type size the simulator is already at: read on the host before a walk and handed to the runner, which records it in the manifest (SimWalk#288).
///
/// **A walk run after `simctl ui <udid> content_size accessibility-extra-large` captures every screen at that size**, and only a state's `dynamicTypeSize` told the bundle so; `bundle audit` then judged `largeTypeOverflow` not applicable on the very bundles it was written for. Reading the device's own size is what lets `EffectiveTypeSize` answer for a state that sets none.
public struct DeviceContentSize {
    /// The device's size as a `UICTContentSizeCategory…` name, or `nil` when it could not be read or named something this tool has no category for.
    ///
    /// Never throws: a read that fails records nothing.
    public static func read(udid: String, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard let result = try? run("/usr/bin/xcrun", readArguments(udid: udid)), result.succeeded, !result.truncated else { return nil }
        return ContentSizeCategoryName.category(forSimctl: result.standardOutput.trimmed)
    }

    /// `simctl ui <udid> content_size`, which prints one size name.
    public static func readArguments(udid: String) -> [String] {
        ["simctl", "ui", udid, "content_size"]
    }
}
