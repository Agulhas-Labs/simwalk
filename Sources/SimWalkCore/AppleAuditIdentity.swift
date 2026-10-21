//
// Copyright © Agulhas Labs
//

import Foundation

/// Who an Apple audit finding is about, by what the app exposes and never by where it was drawn.
///
/// Screen, the audit's issue type, the element's type, and its identifier (else its label, else Apple's compact description), then its place among findings alike in those in one capture. **Never the frame**: the record's frame is read after the audit, which can scroll, so it need not line up with the state's tree. Two states' findings with this key are one finding seen twice.
public struct AppleAuditIdentity: Hashable, Sendable {
    public let screenID: String
    /// The record's issue type (`contrast`, `hitRegion`, `unknown(…)`).
    public let issueType: String
    /// The element's type by the tree's name; `nil` for an issue with no element.
    public let elementType: String?
    public let name: String
    /// Its place among equal findings in one capture, in the order Apple reported them.
    public let place: Int

    /// The identifier, else the label, of an element that has either.
    public static func name(of element: AppleAuditRecord.Element?) -> String? {
        [element?.identifier, element?.label].compactMap(\.self).first { !$0.isEmpty }
    }

    /// The identities of one capture's issues, in the order given.
    public static func identities(of issues: [AppleAuditRecord.Issue], screenID: String) -> [AppleAuditIdentity] {
        var seen: [AppleAuditIdentity: Int] = [:]
        return issues.map { issue in
            let element = issue.element
            let name = name(of: element) ?? issue.compactDescription
            let base = AppleAuditIdentity(screenID: screenID, issueType: issue.type, elementType: element?.type, name: name, place: 0)
            let place = seen[base, default: 0]
            seen[base] = place + 1
            return AppleAuditIdentity(screenID: screenID, issueType: issue.type, elementType: element?.type, name: name, place: place)
        }
    }
}
