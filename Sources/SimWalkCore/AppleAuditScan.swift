//
// Copyright © Agulhas Labs
//

import Foundation

/// Every capture's Apple audit record read once, for the seven `apple*` rules of `bundle audit`.
///
/// **A capture is exactly one of four things**: audited (its record read, the call returned), failed (the record says the call threw: not checked there), unreadable (the entry names a file that is missing or malformed: not checked there, named with its path), or not recorded (no entry). Only the first is evidence of anything, and none of the other three is ever clean.
public struct AppleAuditScan: Sendable {
    /// Every capture in the manifest.
    public let captureCount: Int
    /// Captures whose record was read and whose call returned.
    public let audited: Int
    /// Captures whose call threw, with why; their issues, found before the throw, stay in ``findings``.
    public let failures: [Failure]
    /// The failures that are XCTest's audit timeout (``AppleAuditRecord/timedOut``), in manifest order.
    public let timeouts: [Failure]
    public let unreadable: [Unreadable]
    public let findings: [Finding]

    public var failed: Int {
        failures.count
    }

    /// Captures with an entry, however it came out.
    public var recorded: Int {
        audited + failed + unreadable.count
    }

    /// The timed-out audits whose records are on disk under `bundleURL`, read without its manifest, in path order; a record that cannot be read is skipped.
    ///
    /// For a bundle whose manifest was never finalised (SimWalk#190): the runner stopped or crashed after an audit timed out, so there is no manifest for ``init(_:)`` to scan, yet the record is on disk and the device's `testmanagerd` is still computing that audit (SimWalk#173). Each timeout is named by its directory, its screen by its slug.
    public static func timeouts(recordedIn bundleURL: URL, fileManager: FileManager = .default) -> [Failure] {
        let decoder = JSONDecoder()
        return CaptureBundleLayout.appleAuditStates(in: bundleURL, fileManager: fileManager).compactMap { state in
            let url = CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.appleAuditPath(screenID: state.screenSlug, stateSlug: state.stateSlug), in: bundleURL)
            guard let record = try? decoder.decode(AppleAuditRecord.self, from: Data(contentsOf: url)), record.timedOut, let error = record.error else { return nil }
            return Failure(screenID: state.screenSlug, stateSlug: state.stateSlug, error: error)
        }
    }

    /// Reads the record of every capture that has an entry.
    public init(_ bundle: CaptureBundle) {
        var audited = 0
        var failures: [Failure] = []
        var timeouts: [Failure] = []
        var unreadable: [Unreadable] = []
        var findings: [Finding] = []
        var count = 0
        let decoder = JSONDecoder()
        for screen in bundle.manifest.screens {
            for capture in screen.captures {
                count += 1
                guard let entry = capture.appleAudit else { continue }
                let url = CaptureBundleLayout.url(forRelativePath: entry.path, in: bundle.url)
                let record: AppleAuditRecord
                do {
                    record = try decoder.decode(AppleAuditRecord.self, from: Data(contentsOf: url))
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    unreadable.append(Unreadable(path: entry.path, reason: "file missing"))
                    continue
                } catch {
                    unreadable.append(Unreadable(path: entry.path, reason: "malformed"))
                    continue
                }
                if let error = record.error {
                    failures.append(Failure(screenID: screen.id, stateSlug: capture.state.slug, error: error))
                    if record.timedOut {
                        timeouts.append(Failure(screenID: screen.id, stateSlug: capture.state.slug, error: error))
                    }
                } else {
                    audited += 1
                }
                let identities = AppleAuditIdentity.identities(of: record.issues, screenID: screen.id)
                for (issue, identity) in zip(record.issues, identities) {
                    findings.append(Finding(screenID: screen.id, stateSlug: capture.state.slug, issue: issue, identity: identity, elementsRead: record.elementsRead == true))
                }
            }
        }
        captureCount = count
        self.audited = audited
        self.failures = failures
        self.timeouts = timeouts
        self.unreadable = unreadable
        self.findings = findings
    }

    /// The residue line naming which captures failed and why, one group per distinct reason with every screen and its states it applies to; `nil` when none did.
    var failureLine: String? {
        guard !failures.isEmpty else { return nil }
        var reasons: [String] = []
        var groups: [String: [ScreenStates]] = [:]
        for failure in failures {
            if groups[failure.reason] == nil {
                reasons.append(failure.reason)
            }
            var screens = groups[failure.reason] ?? []
            if let index = screens.firstIndex(where: { $0.screenID == failure.screenID }) {
                screens[index].states.append(failure.stateSlug)
            } else {
                screens.append(ScreenStates(screenID: failure.screenID, states: [failure.stateSlug]))
            }
            groups[failure.reason] = screens
        }
        let described = reasons.map { reason in
            "\(reason): " + (groups[reason] ?? []).map { "\($0.screenID) [\($0.states.joined(separator: ", "))]" }.joined(separator: ", ")
        }
        return "apple audit: \(failures.count) capture\(failures.count == 1 ? "" : "s") failed, not checked there — \(described.joined(separator: "; "))"
    }

    /// The findings of one issue type.
    public func findings(ofType type: String) -> [Finding] {
        findings.filter { $0.issue.type == type }
    }

    /// Issues of a type no rule reads, by the type's name with how many, in first-seen order.
    public var unread: [(type: String, count: Int)] {
        let read = Set(AuditRuleName.allCases.compactMap(\.appleIssueType))
        var order: [String] = []
        var counts: [String: Int] = [:]
        for finding in findings where !read.contains(finding.issue.type) {
            if counts[finding.issue.type] == nil {
                order.append(finding.issue.type)
            }
            counts[finding.issue.type, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }
}

private extension AppleAuditScan {
    struct ScreenStates {
        let screenID: String
        var states: [String]
    }
}

public extension AppleAuditScan {
    /// One issue found in one capture.
    struct Finding: Sendable {
        public let screenID: String
        public let stateSlug: String
        public let issue: AppleAuditRecord.Issue
        public let identity: AppleAuditIdentity
        /// Whether the finding's record says each issue's element was read after the audit.
        public let elementsRead: Bool

        var elementCase: AppleElementCase {
            AppleElementCase(issue, elementsRead: elementsRead)
        }
    }

    /// A capture whose audit call threw.
    struct Failure: Equatable, Sendable {
        public let screenID: String
        public let stateSlug: String
        /// The text inside the error's first pair of double quotes when it has one (Apple's own sentence), else the error trimmed.
        public let reason: String

        init(screenID: String, stateSlug: String, error: String) {
            self.screenID = screenID
            self.stateSlug = stateSlug
            let quoted = error.split(separator: "\"", omittingEmptySubsequences: false)
            reason = quoted.count >= 3 && !quoted[1].isEmpty ? String(quoted[1]) : AuditRowFormat.trim(error)
        }
    }

    /// A record the manifest names that could not be read.
    struct Unreadable: Equatable, Sendable {
        public let path: String
        public let reason: String
    }
}
