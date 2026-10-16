//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A walkbook's `oracle` and a screen's `figures`, held to the same strict keys and `validate` refusals as every other field.
struct WalkbookFigureTests {
    private static var screen: String {
        #""id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}]"#
    }

    @Test
    func anOracleAndItsFiguresDecode() throws {
        let walkbook = try WalkbookLoader.load(from: Data(#"{"name":"w","appBundleID":"a.b","oracle":{"command":["./oracle.sh","--store","seed"]},"screens":[{\#(Self.screen),"figures":[{"id":"steps-today","element":"Steps {n}","windows":["midnight","rolling24h"]}]}]}"#.utf8), source: "w.json")

        #expect(walkbook.oracle == Walkbook.Oracle(command: ["./oracle.sh", "--store", "seed"]))
        #expect(walkbook.screens[0].figures == [Walkbook.Figure(id: "steps-today", element: "Steps {n}", windows: ["midnight", "rolling24h"])])
    }

    @Test
    func figuresWithoutAnOracleAndBadFiguresAreEachRefused() throws {
        let problems = try Self.refusal(#"{"name":"w","appBundleID":"a.b","screens":[{\#(Self.screen),"figures":[{"id":"steps","element":"a","windows":[]},{"id":"steps","element":"{n} of {n}","windows":["midnight"]}]}]}"#)

        #expect(problems == [
            .figuresWithoutOracle(screenID: "today", index: 0),
            .emptyFigureWindows(screenID: "today", index: 0, figureID: "steps"),
            .figureElementPlaceholders(screenID: "today", index: 0, figureID: "steps", count: 2),
            .duplicateFigureID(screenID: "today", index: 0, figureID: "steps"),
        ])
    }

    @Test
    func unknownFigureAndOracleKeysAreNamedWithWhatWasMeant() throws {
        let problems = try Self.refusal(#"{"name":"w","appBundleID":"a.b","oracle":{"comand":["x"]},"screens":[{\#(Self.screen),"figures":[{"id":"s","element":"e","window":["midnight"]}]}]}"#)

        #expect(problems.contains(.unknownKey(path: "oracle", key: "comand", suggestion: "command")))
        #expect(problems.contains(.unknownKey(path: "screens[0].figures[0]", key: "window", suggestion: "windows")))
    }

    @Test
    func anOracleNamingNoExecutableIsRefused() throws {
        let problems = try Self.refusal(#"{"name":"w","appBundleID":"a.b","oracle":{"command":[]},"screens":[{\#(Self.screen)}]}"#)

        #expect(problems == [.emptyOracleCommand])
    }

    private static func refusal(_ json: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [WalkbookProblem] {
        do {
            _ = try WalkbookLoader.load(from: Data(json.utf8), source: "w.json")
        } catch let WalkbookLoadError.invalid(_, problems) {
            return problems
        }
        Issue.record("expected a refusal", sourceLocation: sourceLocation)
        return []
    }
}
