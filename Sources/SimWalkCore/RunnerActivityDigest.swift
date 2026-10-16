//
// Copyright © Agulhas Labs
//

import Foundation

/// What a failed runner's result bundle says happened just before it failed: the last activities XCTest recorded, the failure itself, and the attachments its failure triage left (SimWalk#50).
///
/// Read from the JSON `xcrun xcresulttool get test-results activities` prints — checked against `xcresulttool` version 25115, schema 0.4.0: `testRuns[].activities[]`, each activity a `title`, an `isAssociatedWithFailure`, optional `attachments` (`name`, `uuid`) and optional `childActivities`. The tree is flattened in the order XCTest recorded it, parent before child, because the step that failed is usually a leaf — `Find the Any (Element at index 1)` under the tap that asked for it.
///
/// **The failure is the last one recorded.** The runner sets `continueAfterFailure`, so a walk can record a failure and carry on; the one that ended it without a bundle is the last, and the earlier ones are counted rather than listed. A failure is an activity marked with it and none of whose children is — a parent marked because a child failed is context, not a second failure.
///
/// **The triage is set aside, not listed.** XCTest records a `Collecting debug information to assist test failure triage` activity before each failure, holding the hierarchy snapshot and a screenshot; its titles would be four of the ten and say nothing. Its attachments are what a reader wants, so they are kept apart, for the driver to export.
///
/// Pure — JSON in, a digest out — and `nil` when there is nothing to show: an empty or foreign document, or a run with no failure in it. Never a throw, because this only ever adds to a refusal that is already being made.
public struct RunnerActivityDigest: Equatable, Sendable {
    /// The activities recorded before the failure, oldest first — at most ``recentLimit``.
    public let recentActivities: [String]
    /// The failure's own title: the assertion's message, or the error the test threw.
    public let failure: String
    /// How many failures were recorded before this one.
    public let earlierFailures: Int
    /// What the triage recorded just before the failure attached — empty when there was no triage.
    public let triageAttachments: [Attachment]

    public init(recentActivities: [String], failure: String, earlierFailures: Int, triageAttachments: [Attachment]) {
        self.recentActivities = recentActivities
        self.failure = failure
        self.earlierFailures = earlierFailures
        self.triageAttachments = triageAttachments
    }

    /// How many activities before the failure a digest keeps.
    public static let recentLimit = 10

    /// The prefix of the name XCTest gives the hierarchy text a triage attaches — `App UI hierarchy for <bundle id>…`.
    public static var hierarchyNamePrefix: String {
        "App UI hierarchy"
    }

    /// The triage attachments that are the app's UI hierarchy, as text.
    public var hierarchyAttachments: [Attachment] {
        triageAttachments.filter { $0.name.hasPrefix(Self.hierarchyNamePrefix) }
    }

    /// The digest of an activities document, or `nil` when it holds no failure to show.
    public static func parse(_ data: Data) -> RunnerActivityDigest? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }
        var entries: [Entry] = []
        for run in document.testRuns {
            for activity in run.activities ?? [] {
                flatten(activity, into: &entries)
            }
        }
        guard let failureIndex = entries.lastIndex(where: \.isFailure), case let .failure(failure) = entries[failureIndex] else { return nil }
        let before = entries[..<failureIndex]
        // The triage credited to this failure is one recorded after the *previous* failure, never one an
        // earlier failure left behind — a last failure with no triage of its own exports nothing, rather than
        // handing its refusal an earlier failure's hierarchy under its own label.
        let previousFailureIndex = before.lastIndex(where: \.isFailure)
        let sinceLastFailure = previousFailureIndex.map { before[before.index(after: $0)...] } ?? before
        let triage = sinceLastFailure.last {
            if case .triage = $0 {
                true
            } else {
                false
            }
        }
        return RunnerActivityDigest(
            recentActivities: Array(before.compactMap(\.listedTitle).suffix(recentLimit)),
            failure: failure,
            earlierFailures: before.count(where: \.isFailure),
            triageAttachments: triage?.attachments ?? []
        )
    }

    /// Which of the files an `xcresulttool export attachments` run wrote are ``hierarchyAttachments``, in this digest's order.
    ///
    /// `xcresulttool` 25115 names each exported file by its attachment's `uuid` plus an extension (`467AD7EA-….txt`), so that is what is matched; an attachment with no `uuid`, or one the export did not write, names no file.
    public func exportedHierarchyFiles(among fileNames: [String]) -> [String] {
        hierarchyAttachments.compactMap { attachment in
            guard let uuid = attachment.uuid else { return nil }
            return fileNames.first { ($0 as NSString).deletingPathExtension == uuid }
        }
    }

    private static func flatten(_ activity: Activity, into entries: inout [Entry]) {
        let title = activity.title ?? ""
        if title.hasPrefix(triageTitlePrefix) {
            entries.append(.triage(attachments(under: activity)))
            return
        }
        let children = activity.childActivities ?? []
        if activity.isAssociatedWithFailure == true, !children.contains(where: { $0.isAssociatedWithFailure == true }) {
            entries.append(.failure(title))
        } else if !title.isEmpty {
            entries.append(.activity(title))
        }
        for child in children {
            flatten(child, into: &entries)
        }
    }

    private static func attachments(under activity: Activity) -> [Attachment] {
        let own = (activity.attachments ?? []).map { Attachment(name: $0.name, uuid: $0.uuid) }
        // A parent lists its children's attachments too, so the children are read only when it listed none.
        guard own.isEmpty else { return own }
        return (activity.childActivities ?? []).flatMap(attachments(under:))
    }

    private static var triageTitlePrefix: String {
        "Collecting debug information to assist test failure triage"
    }
}

public extension RunnerActivityDigest {
    /// One file XCTest attached: its name, and the identifier the exported file is named by.
    struct Attachment: Equatable, Sendable {
        public let name: String
        public let uuid: String?

        public init(name: String, uuid: String?) {
            self.name = name
            self.uuid = uuid
        }
    }
}

private extension RunnerActivityDigest {
    /// One activity in the flattened order: a step, a failure, or a triage with what it attached.
    enum Entry {
        case activity(String)
        case failure(String)
        case triage([Attachment])

        var isFailure: Bool {
            if case .failure = self {
                true
            } else {
                false
            }
        }

        /// The title a digest lists: every step and failure that has one, never a triage.
        var listedTitle: String? {
            switch self {
            case let .activity(title), let .failure(title): title.isEmpty ? nil : title
            case .triage: nil
            }
        }

        var attachments: [Attachment] {
            if case let .triage(attachments) = self {
                attachments
            } else {
                []
            }
        }
    }

    struct Document: Decodable {
        let testRuns: [Run]
    }

    struct Run: Decodable {
        let activities: [Activity]?
    }

    struct Activity: Decodable {
        let title: String?
        let isAssociatedWithFailure: Bool?
        let attachments: [RawAttachment]?
        let childActivities: [Activity]?
    }

    struct RawAttachment: Decodable {
        let name: String
        let uuid: String?
    }
}
