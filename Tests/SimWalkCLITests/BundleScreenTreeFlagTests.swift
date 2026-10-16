//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import Testing

/// `bundle screen --tree` and `--bars` at the parser (SimWalk#121).
struct BundleScreenTreeFlagTests {
    @Test
    func treeWithoutMatchIsRefusedInTheCommandsOwnWords() {
        let thrown = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk", "1", "--tree"])
        }

        #expect(BundleScreenCommand.message(for: thrown ?? CocoaError(.fileNoSuchFile)).contains("--tree lists the nodes --match names"))
    }

    @Test
    func treeWithMatchAndBarsAloneParse() throws {
        let tree = try BundleScreenCommand.parse(["anywhere.simwalk", "1", "--tree", "--match", "Rows"])
        let bars = try BundleScreenCommand.parse(["anywhere.simwalk", "1", "--bars"])

        #expect(tree.listsTree && tree.match == "Rows" && !tree.bars)
        #expect(bars.bars && !bars.listsTree)
    }
}
