//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The `location` axis: its slug, its validation, and the positive-only check that the capture shows it.
struct LocationStateTests {
    @Test
    func aLocationSlugsByItsHashAfterTheOldAxes() {
        let state = Walkbook.CaptureState(theme: .light, location: Walkbook.Location(latitude: 51.5, longitude: -0.12))

        #expect(state.slug.hasPrefix("light-geo_"))
        #expect(state.slug.count == "light-geo_".count + 8)
        #expect(state.slug != Walkbook.CaptureState(theme: .light, location: Walkbook.Location(latitude: -0.12, longitude: 51.5)).slug)
    }

    @Test
    func aLocationOutOfRangeIsRefused() throws {
        let json = #"{"name":"w","appBundleID":"a","screens":[{"id":"s","route":[{"tab":{"label":"A"}}],"states":[{"theme":"light","location":{"latitude":91,"longitude":-0.12}}]}]}"#

        let error = #expect(throws: WalkbookLoadError.self) { try WalkbookLoader.load(from: Data(json.utf8), source: "w") }
        let refusal = try "\(#require(error))"

        #expect(refusal.contains("requests location 91.0, -0.12"))
    }

    @Test
    func aCaptureShowingTheCoordinateIsVerified() {
        let state = Walkbook.CaptureState(theme: .light, location: Walkbook.Location(latitude: 51.5, longitude: -0.12))
        let tree = Self.screen(showing: "51.50, -0.12")

        let filing = StateApplicationCheck.filing(for: [StateApplicationCheck.Evidence(state: state, screenshot: Data([1]), tree: tree)], instead: .captured)

        #expect(filing.outcome == .captured)
        #expect(filing.unverified.isEmpty)
    }

    /// Another coordinate, or none, is not evidence the location failed — it is filed, set and unverified.
    @Test
    func aCaptureShowingAnotherCoordinateIsFiledUnverified() {
        let state = Walkbook.CaptureState(theme: .light, location: Walkbook.Location(latitude: 51.5, longitude: -0.12))
        let tree = Self.screen(showing: "37.33, -122.03")

        let filing = StateApplicationCheck.filing(for: [StateApplicationCheck.Evidence(state: state, screenshot: Data([1]), tree: tree)], instead: .captured)

        #expect(filing.outcome == .captured)
        #expect(filing.unverified == [StateApplicationCheck.Unverified(state: state, axes: ["location"])])
    }

    /// A whole number is too coarse to count: `52` rounds to half the latitudes near London.
    @Test
    func aWholeNumberDoesNotCountAsTheCoordinate() {
        #expect(!LocationShownCheck.isShown(Walkbook.Location(latitude: 52, longitude: 0), in: Self.screen(showing: "52, 0")))
    }

    private static func screen(showing text: String) -> AXNode {
        AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 200, height: 20), label: text, identifier: "location-value"),
        ])
    }
}
