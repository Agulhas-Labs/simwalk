//
// Copyright © Agulhas Labs
//

import Foundation

/// Apple's accessibility audit of one captured state, filed as `apple-audit.json` in the state's directory (E1a).
///
/// It is Apple's `performAccessibilityAudit` result.
///
/// **A record, not a verdict.** SimWalk files what Apple's audit reported and what it cost; `bundle audit` rules over it are a later change. A state that has the file was audited: ``issues`` empty and ``error`` `nil` is a clean audit, and ``error`` set is an audit whose call threw (recorded, failed) — never a silent gap. A state without the file was not audited.
///
/// **The audit moves the app's scroll position** (the tree differed after it in 12 of 29 measured states), so the runner takes it after the state's capture. Encoded with sorted keys, so the file is deterministic for the same issues apart from ``milliseconds``.
public struct AppleAuditRecord: Codable, Equatable, Sendable {
    /// How long the audit call took, in whole milliseconds.
    public var milliseconds: Int
    /// What the call threw, when it did; `nil` when it returned.
    ///
    /// Issues found before the throw stay in ``issues``.
    public var error: String?
    /// Every issue Apple reported, in the order it reported them.
    public var issues: [Issue]

    public init(milliseconds: Int, error: String? = nil, issues: [Issue] = []) {
        self.milliseconds = milliseconds
        self.error = error
        self.issues = issues
    }

    /// Whether the call threw rather than returned.
    public var failed: Bool {
        error != nil
    }

    /// The encoding the runner files: sorted keys, slashes unescaped.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The stable name of an audit type: `known` when the runner recognised it, else `unknown(<raw>)` so a value Apple adds later is recorded rather than dropped.
    public static func typeName(known: String?, raw: UInt64) -> String {
        known ?? "unknown(\(raw))"
    }
}

public extension AppleAuditRecord {
    /// One issue Apple's audit reported.
    struct Issue: Codable, Equatable, Sendable {
        /// The audit type's stable name (``AppleAuditRecord/typeName(known:raw:)``).
        public var type: String
        public var compactDescription: String
        public var detailedDescription: String
        /// The element Apple names, where it names one.
        public var element: Element?

        public init(type: String, compactDescription: String, detailedDescription: String, element: Element? = nil) {
            self.type = type
            self.compactDescription = compactDescription
            self.detailedDescription = detailedDescription
            self.element = element
        }
    }

    /// The element an issue is about.
    struct Element: Codable, Equatable, Sendable {
        /// The element's type by the name the capture's tree gives it (`Button`, `StaticText`) from the runner's table; a type the SDK adds later is `Type<raw>`.
        public var type: String
        public var identifier: String
        public var label: String
        /// Read after the audit returned, so it need not line up with the state's `screen.png` or tree.
        ///
        /// The audit can move the scroll position.
        ///
        /// Match an issue to the tree by identifier or label, never by frame.
        public var frame: AXNode.Frame

        public init(type: String, identifier: String, label: String, frame: AXNode.Frame) {
            self.type = type
            self.identifier = identifier
            self.label = label
            self.frame = frame
        }
    }
}

public extension CaptureManifest {
    /// Where one state's Apple audit record is and what it came to, so an answer can summarise it without opening the file.
    ///
    /// **Absent means not audited, never clean**; present with ``issueCount`` 0 is an audit that found nothing. **Inside format 8**, as `capturedAt` and ``Motion`` are: a capture decodes leniently, so a reader that predates the key ignores it and loses only the record.
    struct AppleAuditEntry: Codable, Equatable, Sendable {
        /// The record's bundle-relative path; derived from the layout, never assignable from outside the module.
        public private(set) var path: String
        public var milliseconds: Int
        public var issueCount: Int
        /// Whether the audit call threw.
        public var failed: Bool

        init(path: String, milliseconds: Int, issueCount: Int, failed: Bool) {
            self.path = path
            self.milliseconds = milliseconds
            self.issueCount = issueCount
            self.failed = failed
        }

        /// The entry for `record` filed at the layout's path for this state.
        public init(screenID: String, stateSlug: String, record: AppleAuditRecord) {
            self.init(
                path: CaptureBundleLayout.appleAuditPath(screenID: screenID, stateSlug: stateSlug),
                milliseconds: record.milliseconds,
                issueCount: record.issues.count,
                failed: record.failed
            )
        }
    }

    /// Every audited capture's entry, in manifest order.
    var appleAuditEntries: [AppleAuditEntry] {
        screens.flatMap { $0.captures.compactMap(\.appleAudit) }
    }
}
