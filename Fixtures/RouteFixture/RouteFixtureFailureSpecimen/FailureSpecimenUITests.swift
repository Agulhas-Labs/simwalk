//
// Copyright © Agulhas Labs
//

import XCTest

/// THIS TEST FAILS ON PURPOSE. It exists to make the result bundle that `Tests/SimWalkCoreTests/Fixtures/runner-failure-activities.json` is exported from, which `RunnerActivityDigestTests` reads: a failed XCUITest's activities, with an earlier failure, a last failure and XCTest's failure-triage attachments.
///
/// Remake the fixture from the repository root (`<udid>` is any iOS simulator):
///
///     xcodebuild test -project Fixtures/RouteFixture/RouteFixture.xcodeproj -scheme RouteFixtureFailureSpecimen \
///       -destination 'id=<udid>' -derivedDataPath .build/routefixture-dd -resultBundlePath .build/specimen.xcresult
///     xcrun xcresulttool get test-results activities --compact --path .build/specimen.xcresult \
///       --test-id 'FailureSpecimenUITests/testHubDrawsNoRows()'
///
/// then pretty-print the JSON (sorted keys, one space indent) and replace every UUID, user path and host name with a synthetic one.
///
/// After the test fails, `xcodebuild` can sit for ten minutes or more in a `simctl diagnose` child it starts to collect diagnostics, and the result bundle has no `Info.plist` until it ends (measured on Xcode 27, 2026-10-16); ending that child, not `xcodebuild`, leaves a readable bundle. The assertions wait with `waitForExistence(timeout:)` rather than reading `.exists` because only a failed query records XCTest's failure triage, which is what attaches the app UI hierarchy the digest reads.
final class FailureSpecimenUITests: XCTestCase {
    func testHubDrawsNoRows() {
        continueAfterFailure = true

        let app = XCUIApplication()
        app.launchArguments = ["-RouteFixtureTabs"]
        app.launch()

        for tab in ["Rows", "Menus", "Nested", "Hub"] {
            app.tabBars.buttons[tab].tap()
        }
        // The earlier failure.
        XCTAssertTrue(app.staticTexts["Hub row 0"].waitForExistence(timeout: 1), "Hub has no row zero")

        app.tabBars.buttons["Menus"].tap()
        app.tabBars.buttons["Hub"].tap()

        // The last failure.
        XCTAssertTrue(app.staticTexts["Hub row 99"].waitForExistence(timeout: 1), "Hub drew no rows at all")
    }
}
