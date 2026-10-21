//
// Copyright © Agulhas Labs
//

import SwiftUI

/// A generic account screen for SimWalk's README demo: a list of rows, each a title and a value.
///
/// The `SimWalkDemoRegression` user default (`-SimWalkDemoRegression YES` for one launch) switches every row to a layout
/// that overlaps its two texts once the text size is large.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            AccountScreen()
        }
    }
}
