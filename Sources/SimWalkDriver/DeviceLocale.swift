//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The locale the simulator is already in: read on the host before a walk and handed to the runner, so a state asking for the device's own locale is not refused for drawing what the device draws anyway (SimWalk#18).
///
/// **A locale state was refused as not applied on a device already in that locale.** a field walkbook's device is in `en_GB`, so its `light-loc_en_gb` state launched under exactly the conditions `light` did and the two captures came back byte-identical — the correct result, which the identity rule read as a discarded axis. Knowing the device's locale is what lets `StateApplicationCheck` tell "the device ignored it" from "the device already was it".
///
/// **Two keys, and both have to agree.** A walkbook locale launches the app with `-AppleLocale <id> -AppleLanguages (<id>)`, so the plain state matches it only when the device's region format *and* its first preferred language are that locale. A device formatting as `en_GB` and reading `en-US` first is in neither state's conditions, and answers `nil` — which refuses as before.
///
/// Read through the runtime's own `defaults` — the bare name, never `/usr/bin/defaults`, which `simctl spawn` would run from the host against a domain the simulator does not keep there (SimWalk#8).
public struct DeviceLocale {
    /// The device's locale as a Foundation identifier (`en_GB`), when its region format and first preferred language name the same one; `nil` when either cannot be read or they disagree.
    public static func read(udid: String, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard let region = value(of: regionKey, udid: udid, run: run).flatMap(plainLocale),
              let languages = value(of: languagesKey, udid: udid, run: run),
              let language = firstLanguage(in: languages).map(normalized),
              language == region
        else {
            return nil
        }
        return region
    }

    /// `simctl spawn <udid> defaults read -g <key>`, through the runtime's `defaults`.
    public static func readArguments(udid: String, key: String) -> [String] {
        ["simctl", "spawn", udid, runtimeDefaults, "read", "-g", key]
    }

    /// An identifier in the spelling a walkbook uses: BCP-47's hyphen as Foundation's underscore.
    static func normalized(_ identifier: String) -> String {
        identifier.trimmed.replacingOccurrences(of: "-", with: "_")
    }

    /// `AppleLocale` as the plain locale a walkbook state would launch the app in, or `nil` when its `@` keywords make the device draw something that launch argument would not.
    ///
    /// **Stripping the keywords was too permissive** (the SimWalk#18 review). `en_US@rg=gbzzzz` formats as the UK: read as `en_US`, an `en_US` state the app ignored would be filed as applied and identical to its base while drawing UK dates. A walkbook locale launches with a bare `-AppleLocale <id>`, so any keyword that changes region, calendar or numbering — or any this cannot judge — makes the device's own locale one no state reproduces. Only a region keyword naming the locale's own region (`fr_FR@rg=frzzzz`) changes nothing, and is read through.
    static func plainLocale(_ identifier: String) -> String? {
        let parts = identifier.trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        let base = normalized(first)
        guard parts.count == 2 else { return base }
        let ownRegion = base.split(separator: "_").last.map { String($0).uppercased() }
        for keyword in parts[1].split(separator: ";") {
            let pair = keyword.split(separator: "=", maxSplits: 1).map { String($0).lowercased() }
            guard pair.count == 2, pair[0] == "rg", String(pair[1].prefix(2)).uppercased() == ownRegion else {
                return nil
            }
        }
        return base
    }

    /// The first entry of the property-list array `defaults` prints for `AppleLanguages`, quoted or not.
    static func firstLanguage(in printed: String) -> String? {
        printed
            .trimmingCharacters(in: CharacterSet(charactersIn: "() \n\t"))
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t")) }
            .first { !$0.isEmpty }
    }

    private static func value(of key: String, udid: String, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard let result = try? run(xcrun, readArguments(udid: udid, key: key)), result.succeeded, !result.truncated else { return nil }
        let value = result.standardOutput.trimmed
        return value.isEmpty ? nil : value
    }

    private static var regionKey: String {
        "AppleLocale"
    }

    private static var languagesKey: String {
        "AppleLanguages"
    }

    /// The runtime's `defaults`, resolved inside the simulator's root because it is not an absolute path.
    private static var runtimeDefaults: String {
        "defaults"
    }

    private static var xcrun: String {
        "/usr/bin/xcrun"
    }
}
