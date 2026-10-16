//
// Copyright © Agulhas Labs
//

import SimWalkCore
import UIKit
import XCTest

/// Finding a `tab` step's tab in the tree, split from `StepPerformer` for its size (SimWalk#119).
@MainActor
struct TabLocator {
    /// Reads the tree every interval until `TabTarget` finds the tab or `deadline` passes; the last answer when it does not.
    static func locate(_ label: String, in app: XCUIApplication, until deadline: Date) throws -> TabTarget.Location {
        var located = try TabTarget.locate(label, in: AXTreeCapture.tree(of: app))
        while case .missing = located, Date() < deadline {
            Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
            located = try TabTarget.locate(label, in: AXTreeCapture.tree(of: app))
        }
        return located
    }
}
