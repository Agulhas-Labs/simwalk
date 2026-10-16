//
// Copyright © Agulhas Labs
//

import Foundation

/// A physical iPhone's appearance settings as `xcrun devicectl device info appearance` reports them (SimWalk#116).
public struct PhysicalDeviceAppearance: Codable, Equatable, Sendable {
    /// `light` or `dark`.
    public let userInterfaceStyle: String
    /// The text-size category name, e.g. `Large`.
    public let textSize: String
    public let increaseContrast: Bool

    static var commandName: String {
        "devicectl device info appearance"
    }

    public static func parse(appearanceJSON: Data) throws -> PhysicalDeviceAppearance {
        guard let root = try? JSONSerialization.jsonObject(with: appearanceJSON) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let style = result["userInterfaceStyle"] as? String,
              let size = result["textSize"] as? String,
              let contrast = result["increaseContrast"] as? Bool
        else {
            throw PhysicalDeviceError.unreadable(command: commandName, reason: "userInterfaceStyle, textSize or increaseContrast is missing")
        }
        return PhysicalDeviceAppearance(userInterfaceStyle: style, textSize: size, increaseContrast: contrast)
    }

    /// Runs `devicectl device info appearance` against `udid` and parses it.
    public static func read(udid: String, shell: Shell = Shell()) throws -> PhysicalDeviceAppearance {
        let output = try PhysicalDevicePrerequisites.devicectl(["device", "info", "appearance", "--device", udid], command: commandName, shell: shell)
        return try parse(appearanceJSON: output)
    }

    /// Sets the phone's interface style with `devicectl device settings appearance --mode`.
    public static func setStyle(_ style: String, udid: String, shell: Shell = Shell()) throws {
        _ = try PhysicalDevicePrerequisites.devicectl(
            ["device", "settings", "appearance", "--device", udid, "--mode", style],
            command: "devicectl device settings appearance",
            shell: shell
        )
    }

    /// Sets the phone's Increase Contrast with `devicectl device settings appearance --increase-contrast` (SimWalk#116, ruling 6); the caller judges it by reading the appearance again.
    public static func setIncreaseContrast(_ enabled: Bool, udid: String, shell: Shell = Shell()) throws {
        _ = try PhysicalDevicePrerequisites.devicectl(
            ["device", "settings", "appearance", "--device", udid, "--increase-contrast", enabled ? "on" : "off"],
            command: "devicectl device settings appearance",
            shell: shell
        )
    }

    /// Reads the appearance back and, when the interface style differs from `found`, hands it back with `devicectl` and reads again.
    ///
    /// Never throws: it runs on the way out of a walk that may already be failing, and says what it could not do instead. Text size is reported on a mismatch and never set (Dynamic Type is app-level here, so a mismatch is unexpected).
    ///
    /// `restoringContrast` is for a walk that set Increase Contrast: it is put back to `found` and read again, and judged by that read. Left `false`, contrast is not touched, so a caller that never set it does not undo a change the user made.
    public static func handBack(found: PhysicalDeviceAppearance, udid: String, restoringContrast: Bool = false, shell: Shell = Shell()) -> Handback {
        var lines: [String] = []
        var qualifications: [String] = []
        var current: PhysicalDeviceAppearance
        do {
            current = try read(udid: udid, shell: shell)
        } catch {
            return Handback(
                lines: ["appearance NOT read back (found \(found.userInterfaceStyle)): \(error)"],
                qualifications: ["the device's appearance could not be read back, so it may not be as it was found (\(found.userInterfaceStyle))"],
                contrastNotHandedBack: restoringContrast ? "devicectl device settings appearance --increase-contrast \(found.increaseContrast ? "on" : "off") (the appearance could not be read back)" : nil
            )
        }
        if current.userInterfaceStyle == found.userInterfaceStyle {
            lines.append("appearance handed back: \(found.userInterfaceStyle) (read back)")
        } else {
            let was = current.userInterfaceStyle
            var setFailure = ""
            do {
                try setStyle(found.userInterfaceStyle, udid: udid, shell: shell)
            } catch {
                setFailure = " (devicectl: \(error))"
            }
            let setMade = setFailure.isEmpty
            do {
                current = try read(udid: udid, shell: shell)
            } catch {
                // The first read's text size is the last one known: a text size the walk changed and cannot confirm is still reported.
                if current.textSize != found.textSize {
                    lines.append("text size NOT confirmed: found \(found.textSize), was \(current.textSize), and the re-read failed")
                    qualifications.append("the device's text size could not be confirmed after the walk: found \(found.textSize), was \(current.textSize)")
                }
                // `current` is the pre-set value; printing it as "now" would say the device is as it was before the set.
                lines.append("appearance NOT confirmed: found \(found.userInterfaceStyle), was \(was), \(setMade ? "set by devicectl" : "set NOT made\(setFailure)"), and the re-read failed: \(error)")
                qualifications.append("the device's appearance could not be \(setMade ? "read back after setting it" : "set back or read back"), so it may not be as it was found (\(found.userInterfaceStyle))")
                return Handback(lines: lines, qualifications: qualifications, contrastNotHandedBack: restoringContrast ? contrastCommand(found: found, udid: udid) + " (the appearance could not be read back)" : nil)
            }
            if current.userInterfaceStyle == found.userInterfaceStyle {
                lines.append("appearance handed back by devicectl: found \(found.userInterfaceStyle), was \(was), now \(current.userInterfaceStyle) (read back)")
            } else {
                lines.append("appearance NOT handed back: found \(found.userInterfaceStyle), now \(current.userInterfaceStyle)\(setFailure)")
                qualifications.append("the device's appearance was not handed back: found \(found.userInterfaceStyle), now \(current.userInterfaceStyle)")
            }
        }
        if current.textSize != found.textSize {
            lines.append("text size NOT handed back: found \(found.textSize), now \(current.textSize)")
            qualifications.append("the device's text size was not handed back: found \(found.textSize), now \(current.textSize)")
        }
        var contrastHandedBack: String?
        var contrastNotHandedBack: String?
        if restoringContrast {
            let foundWord = found.increaseContrast ? "on" : "off"
            if current.increaseContrast != found.increaseContrast {
                do {
                    try setIncreaseContrast(found.increaseContrast, udid: udid, shell: shell)
                    current = try read(udid: udid, shell: shell)
                } catch {
                    contrastNotHandedBack = "\(contrastCommand(found: found, udid: udid)) (\(error))"
                }
            }
            if contrastNotHandedBack == nil {
                if current.increaseContrast == found.increaseContrast {
                    contrastHandedBack = "Increase Contrast put back \(foundWord), read back"
                    lines.append("Increase Contrast handed back: \(foundWord) (read back)")
                } else {
                    contrastNotHandedBack = "\(contrastCommand(found: found, udid: udid)) (it read back \(current.increaseContrast ? "on" : "off"))"
                }
            }
            if let failed = contrastNotHandedBack {
                lines.append("Increase Contrast NOT handed back: found \(foundWord) — run: \(failed)")
                qualifications.append("the device's Increase Contrast was not handed back: found \(foundWord)")
            }
        }
        return Handback(lines: lines, qualifications: qualifications, contrastHandedBack: contrastHandedBack, contrastNotHandedBack: contrastNotHandedBack)
    }

    private static func contrastCommand(found: PhysicalDeviceAppearance, udid: String) -> String {
        "xcrun devicectl device settings appearance --device \(udid) --increase-contrast \(found.increaseContrast ? "on" : "off")"
    }
}

public extension PhysicalDeviceAppearance {
    /// What came of putting the phone's appearance back as the walk found it.
    struct Handback: Equatable, Sendable {
        /// Lines for an answer or a refusal to carry, whichever way it went.
        public let lines: [String]
        /// What qualifies an answer: the phone was left in a state it was not found in.
        public let qualifications: [String]
        /// What Increase Contrast was put back to and read back as, for the manifest's record; `nil` when the walk did not set it or could not put it back.
        public var contrastHandedBack: String?
        /// The command a person must run when Increase Contrast could not be put back or read back as found; `nil` otherwise.
        public var contrastNotHandedBack: String?

        public init(lines: [String], qualifications: [String], contrastHandedBack: String? = nil, contrastNotHandedBack: String? = nil) {
            self.lines = lines
            self.qualifications = qualifications
            self.contrastHandedBack = contrastHandedBack
            self.contrastNotHandedBack = contrastNotHandedBack
        }
    }
}
