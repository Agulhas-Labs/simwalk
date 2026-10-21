//
// Copyright © Agulhas Labs
//

import Foundation

/// One test case of a ``JUnitReport``: a class name and a name, and how it came out.
public struct JUnitCase: Equatable, Sendable {
    public let classname: String
    public let name: String
    public let result: Result

    public init(classname: String, name: String, result: Result) {
        self.classname = classname
        self.name = name
        self.result = result
    }
}

public extension JUnitCase {
    /// How the case came out; every non-passing case carries the reason a reader would otherwise open the text answer for.
    enum Result: Equatable, Sendable {
        case passed
        case failed(String)
        case errored(String)
        case skipped(String)
    }
}
