//
// Copyright © Agulhas Labs
//

import Foundation

public extension CaptureManifest {
    /// The walkbook's `setup` as the host made it on the device, and what its handback put back — written into the manifest by the host after the handback, since the runner never touches the device's settings.
    ///
    /// **Absent rather than empty, and inside format 8**, as `appearanceSettle` is: a manifest with no setup is byte-for-byte what it was before the field existed, and a reader that predates it reads every capture correctly — what it misses is why the device looked as it did, not a fact about any capture.
    struct SetupRecord: Codable, Equatable, Sendable {
        /// Each change made, in the order made — `privacy grant location`, then the status bar and Increase Contrast, each saying whether anything captured verifies it.
        public var made: [String]
        /// Why the status bar override was not set again after an appearance settle rebooted the device — `nil` when it was, or no settle rebooted it.
        public var statusBarNotReapplied: String?
        /// What the handback put back and read back as found.
        public var handedBack: [String]
        /// What the handback put back but could not read back as found, each saying why (SimWalk#63) — `nil` when there was none, so a record without any is byte-for-byte what it was before the field existed.
        public var handedBackUnconfirmed: [String]?
        /// The commands the handback could not run, or that read back wrong, for a person to run.
        public var notHandedBack: [String]
        /// What an earlier walk left on the device and never handed back, as this walk settled it before its own setup (SimWalk#72) — `nil` when there was none, so a record without one is byte-for-byte what it was before the field existed.
        public var leftover: [String]?

        /// How every record of Increase Contrast begins, written by the setups and read by `bundle labels`: one spelling, so rewording a record cannot turn its evidence into a gap.
        public static var increaseContrastPrefix: String {
            "Increase Contrast enabled"
        }

        public init(made: [String], statusBarNotReapplied: String? = nil, handedBack: [String], unconfirmed: [String] = [], notHandedBack: [String], leftover: [String] = []) {
            self.leftover = leftover.isEmpty ? nil : leftover
            self.made = made
            self.statusBarNotReapplied = statusBarNotReapplied
            self.handedBack = handedBack
            handedBackUnconfirmed = unconfirmed.isEmpty ? nil : unconfirmed
            self.notHandedBack = notHandedBack
        }

        /// The record as printed — by `bundle inspect`, and under a walk's answer.
        public var lines: [String] {
            ["setup: \(made.isEmpty ? "none made by this walk" : made.joined(separator: "; "))"]
                + (statusBarNotReapplied.map { ["⚠ setup: the status bar override was not set again after the appearance settle rebooted the device (\($0)), so the screens walked again show the device's own"] } ?? [])
                + (leftover ?? [])
                + Self.handbackLines(handedBack: handedBack, unconfirmed: handedBackUnconfirmed ?? [], notHandedBack: notHandedBack)
        }

        /// A leftover handed back before this walk's setup: whose process left it, what it held, and whether its handback read back as found.
        public static func leftoverLines(pid: Int32, thisProcess: Bool, bundleID: String, made: [String], handedBack: [String], unconfirmed: [String], before: String = "this walk's setup") -> [String] {
            let confirmed = unconfirmed.isEmpty ? "read back as found" : "not confirmed as found: \(unconfirmed.joined(separator: "; "))"
            return ["⚠ setup leftover: pid \(pid) (\(thisProcess ? "an earlier walk in this process" : "no longer running")) made \(made.joined(separator: "; ")) for \(bundleID) and never handed it back; handed back before \(before), \(confirmed)"]
                + (handedBack.isEmpty ? [] : ["setup leftover handed back: \(handedBack.joined(separator: "; "))"])
        }

        /// A leftover record that does not read, moved aside rather than lost.
        public static func unreadableLeftoverLines(path: String, keptAt: String, reason: String) -> [String] {
            ["⚠ setup leftover: \(path) does not read as a setup record (\(reason)), so what an earlier walk may have left on the device can neither be said nor handed back; kept at \(keptAt) for a person to read"]
        }

        /// What a handback put back, what it put back unconfirmed, and the commands it could not run, a line each — one wording for the record and for a setup refused before the runner ran.
        public static func handbackLines(handedBack: [String], unconfirmed: [String] = [], notHandedBack: [String]) -> [String] {
            (handedBack.isEmpty ? [] : ["setup handed back: \(handedBack.joined(separator: "; "))"])
                + unconfirmed.map { "⚠ setup handed back: \($0)" }
                + notHandedBack.map { "⚠ setup not handed back — run: \($0)" }
        }

        /// Writes this record into `bundle`'s manifest and returns the bundle as it now reads; no artefact moves.
        @discardableResult
        public func write(into bundle: CaptureBundle, fileManager: FileManager = .default) throws -> CaptureBundle {
            var manifest = bundle.manifest
            manifest.deviceSetup = self
            return try CaptureBundleWriter(reopening: bundle.url, fileManager: fileManager).finalise(manifest)
        }
    }
}
