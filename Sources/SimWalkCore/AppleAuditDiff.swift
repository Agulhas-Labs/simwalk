//
// Copyright © Agulhas Labs
//

import Foundation

/// The comparison of two bundles' Apple accessibility-audit records (E1b): the issues the run has and the reference lacks.
///
/// **Identity, never frame.** An issue is its type, its element's type and name (identifier, else label) and Apple's compact description, so "Contrast nearly passed" becoming "Contrast failed" on one element is a new issue. The record's frame is read after the audit, which can scroll, so it never decides a match. Issues are compared as a multiset per state: the run's count of a key above the reference's is that many flags. An issue only the reference has is not a flag.
struct AppleAuditDiff {
    var flags: [ScreenDiff.AppleFlag] = []
    var notes: [ScreenDiff.AppleNote] = []
    /// Whether any state had both sides audited, so that no flag means no new issue.
    var compared = false

    /// The side that is the only one holding any record, or `nil`; the bundle-level case that replaces a note per state.
    static func unauditedSide(reference: Records, run: Records) -> BundleDiff.Side? {
        switch (reference.hasRecords, run.hasRecords) {
        case (true, false): .run
        case (false, true): .reference
        default: nil
        }
    }

    /// One paired state: the run's issues above the reference's as flags, or a note for each side that cannot be read.
    static func compare(screenID: String, reference: (records: Records, capture: CaptureManifest.StateCapture), run: (records: Records, capture: CaptureManifest.StateCapture)) -> AppleAuditDiff {
        let slug = reference.capture.state.slug
        let referenceIssues = reference.records.issues(screenID: screenID, capture: reference.capture)
        let runIssues = run.records.issues(screenID: screenID, capture: run.capture)
        guard case let .success(referenceFindings) = referenceIssues, case let .success(runFindings) = runIssues else {
            var notes: [ScreenDiff.AppleNote] = []
            if case let .failure(reason) = referenceIssues {
                notes.append(ScreenDiff.AppleNote(slug: slug, side: .reference, reason: reason))
            }
            if case let .failure(reason) = runIssues {
                notes.append(ScreenDiff.AppleNote(slug: slug, side: .run, reason: reason))
            }
            return AppleAuditDiff(notes: notes)
        }
        var remaining: [Key: Int] = [:]
        for finding in referenceFindings {
            remaining[Key(finding), default: 0] += 1
        }
        let flags = runFindings.compactMap { finding -> ScreenDiff.AppleFlag? in
            let key = Key(finding)
            if let left = remaining[key], left > 0 {
                remaining[key] = left - 1
                return nil
            }
            return ScreenDiff.AppleFlag(slug: slug, issue: finding.issue, elementsRead: finding.elementsRead)
        }
        return AppleAuditDiff(flags: flags, compared: true)
    }
}

extension ScreenDiff.AppleNote.Reason: Error {}

extension AppleAuditDiff {
    /// Why one state's audits were not compared.
    typealias Reason = ScreenDiff.AppleNote.Reason

    /// What each bundle's captures say, read once for the whole diff.
    struct Records {
        let scan: AppleAuditScan

        init(_ bundle: CaptureBundle) {
            scan = AppleAuditScan(bundle)
        }

        /// Whether any capture has an entry, however it came out.
        var hasRecords: Bool {
            scan.recorded > 0
        }

        /// The capture's issues, or why it cannot be read as evidence.
        func issues(screenID: String, capture: CaptureManifest.StateCapture) -> Result<[AppleAuditScan.Finding], Reason> {
            guard let entry = capture.appleAudit else { return .failure(.notAudited) }
            if scan.unreadable.contains(where: { $0.path == entry.path }) {
                return .failure(.unreadable)
            }
            let slug = capture.state.slug
            if scan.failures.contains(where: { $0.screenID == screenID && $0.stateSlug == slug }) {
                return .failure(.failed)
            }
            return .success(scan.findings.filter { $0.screenID == screenID && $0.stateSlug == slug })
        }
    }

    /// What makes two issues one: the finding's identity without its place, and Apple's compact description.
    private struct Key: Hashable {
        let issueType: String
        let elementType: String?
        let name: String
        let description: String

        init(_ finding: AppleAuditScan.Finding) {
            issueType = finding.identity.issueType
            elementType = finding.identity.elementType
            name = finding.identity.name
            description = finding.issue.compactDescription
        }
    }
}
