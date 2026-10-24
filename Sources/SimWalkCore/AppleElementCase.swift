//
// Copyright © Agulhas Labs
//

import Foundation

/// Which of four things an issue's element is, so a reader says only what the record supports.
enum AppleElementCase: Hashable {
    /// Apple named an element and the runner read it.
    case named
    /// The record says Apple named none.
    case noneNamed
    /// Apple named one and reading it after the audit failed.
    case unreadable
    /// A record written before the runner recorded either, with no element: none named or lost, not told apart.
    case unknown

    init(_ issue: AppleAuditRecord.Issue, elementsRead: Bool) {
        if issue.element != nil {
            self = .named
        } else if issue.elementUnreadable != nil {
            self = .unreadable
        } else {
            self = elementsRead ? .noneNamed : .unknown
        }
    }

    /// What stands where an element's type would, for an issue with no element: `Apple named no element`, `the element could not be read after the audit (<error, ~80 characters>)`, or `(no element)` where the record cannot say which.
    static func absentText(unreadable: String?, elementsRead: Bool) -> String {
        if let unreadable {
            let reason = unreadable.count <= 80 ? unreadable : String(unreadable.prefix(79)) + "…"
            return "the element could not be read after the audit (\(reason))"
        }
        return elementsRead ? "Apple named no element" : "(no element)"
    }
}
