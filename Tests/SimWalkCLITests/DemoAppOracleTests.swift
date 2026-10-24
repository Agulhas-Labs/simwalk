//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// The walk-free half of the demo app's value oracle: the committed walkbook, the committed oracle script and CSV, and two trees from a real walk, answered through `bundle oracle` without a simulator.
struct DemoAppOracleTests {
    /// The real walk's answer, reproduced: each figure matches the window the app computed it over (the data total is the rolling 24 hours, the count and the average are since midnight), in both locales, and the verdict is clean.
    @Test
    func everyFigureMatchesTheWindowTheAppComputedItOver() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, dataWindows: nil)
        let recorder = StreamRecorder()

        try run.run(log: BundleOracleCommandTests.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        let text = recorder.out.joined()

        #expect(text.contains("usage/light-loc_en_us downloads-today: 9 matches today (exact) — today 9, last24h 16 downloads"))
        #expect(text.contains("usage/light-loc_en_us data-today: 2,567.3 MB matches last24h"))
        #expect(text.contains("usage/light-loc_en_us average-download: 141.4 MB matches today (±0.05) — today 141.4, last24h 160.4563 MB"))
        #expect(text.contains("usage/light-loc_de_de downloads-today: 9 matches today (exact) — today 9, last24h 16 downloads"))
        #expect(text.contains("usage/light-loc_de_de data-today: 2.567,3 MB matches last24h"))
        #expect(text.contains("usage/light-loc_de_de average-download: 141,4 MB matches today (±0.05) — today 141.4, last24h 160.4563 MB"))
        #expect(text.contains("ok — 6 of 6 figure checks matched"))
        #expect(recorder.err.isEmpty)
    }

    /// Offering the data total only the `today` window finds no match, in both locales, while the other four figures still match: the oracle is what decides, so a figure nobody can reproduce qualifies the answer.
    @Test
    func aFigureOfferedOnlyTheWrongWindowMatchesNoneAndQualifies() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, dataWindows: ["today"])

        let recorder = try BundleOracleCommandTests.expectExit(AnswerVerdict.qualifiedExitCode, running: run, in: directory)

        let text = recorder.out.joined()

        #expect(text.contains("usage/light-loc_en_us data-today: 2,567.3 MB matches none"))
        #expect(text.contains("usage/light-loc_de_de data-today: 2.567,3 MB matches none"))
        #expect(text.contains("usage/light-loc_en_us downloads-today: 9 matches today"))
        #expect(text.contains("usage/light-loc_de_de average-download: 141,4 MB matches today"))
        #expect(text.contains("4 of 6 figure checks matched"))
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The committed walkbook with only its oracle command replaced, and a bundle of the two captured trees stamped with the times the walk took them.
    ///
    /// "Today" is local midnight, so the oracle runs in Europe/London, the zone the walk ran in (BST); the suite itself runs in any zone, and without the pin the nine downloads since that midnight would move. It also runs under a comma-decimal locale, as it would on a Mac set to a German region: `awk` reads and prints numbers in the locale's form unless the script pins its own, and a reply printing `1272,6` is not JSON.
    private static func setUp(in directory: TemporaryDirectory, dataWindows: [String]?, sourceLocation: SourceLocation = #_sourceLocation) throws -> BundleOracleCommand {
        let demo = repositoryRoot.appendingPathComponent("Fixtures/DemoApp")
        var book = try WalkbookLoader.load(contentsOf: demo.appendingPathComponent("downloads.walkbook.json"))
        book.oracle = Walkbook.Oracle(command: ["/usr/bin/env", "TZ=Europe/London", "LC_ALL=de_DE.UTF-8", demo.appendingPathComponent("downloads-oracle.sh").path])
        if let dataWindows {
            let index = try #require(book.screens[0].figures?.firstIndex { $0.id == "data-today" }, sourceLocation: sourceLocation)
            book.screens[0].figures?[index].windows = dataWindows
        }
        let walkbookURL = directory.url.appendingPathComponent("walkbook.json")
        try JSONEncoder().encode(book).write(to: walkbookURL)
        let hash = try WalkbookIdentity.hash(of: WalkbookLoader.load(contentsOf: walkbookURL))
        let bundle = try CaptureBundleFixture.write(
            in: directory,
            captures: [
                CaptureBundleFixture.Capture(
                    screenID: "usage",
                    state: Walkbook.CaptureState(theme: .light, locale: "en_US"),
                    tree: tree("demo-usage-en_us", sourceLocation: sourceLocation),
                    capturedAt: timestamp("2026-10-24T08:36:48.870Z", sourceLocation: sourceLocation)
                ),
                CaptureBundleFixture.Capture(
                    screenID: "usage",
                    state: Walkbook.CaptureState(theme: .light, locale: "de_DE"),
                    tree: tree("demo-usage-de_de", sourceLocation: sourceLocation),
                    capturedAt: timestamp("2026-10-24T08:36:54.773Z", sourceLocation: sourceLocation)
                ),
            ],
            walkbookHash: hash
        )
        return try BundleOracleCommand.parse([bundle.url.path, "--walkbook", walkbookURL.path])
    }

    private static func tree(_ name: String, sourceLocation: SourceLocation) throws -> AXNode {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try JSONDecoder().decode(AXNode.self, from: Data(contentsOf: url))
    }

    private static func timestamp(_ text: String, sourceLocation: SourceLocation) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: text), sourceLocation: sourceLocation)
    }
}
