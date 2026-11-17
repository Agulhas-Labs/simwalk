//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle screen` folds a labelled stop's insides into its row (SimWalk#264).
///
/// A node whose label speaks for what is inside it is one row carrying a count, so the listing does not read as VoiceOver saying each child. Only the listing folds; `ScreenDelta` still sees every child.
struct BundleScreenFoldTests {
    /// The issue's shape: an `Other` labelled `8 stars` over eight `Image 'Favourite'`.
    @Test
    func eightImagesUnderALabelledOtherAreOneRowWithACount() throws {
        let answer = try Self.answer(for: [Self.stars()])

        #expect(answer.text.contains("8 stars · Other (8 images inside) · 16,100 311×30"))
        #expect(!answer.text.contains("Favourite · Image"))
        #expect(answer.text.contains("1 text element on screen"))
    }

    /// A SwiftUI combine container (SimWalk#105): its label carries both texts, so they are counted, not listed.
    @Test
    func aCombineContainerFoldsItsTexts() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "Step 3 of 4, Setup",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 20, height: 30), label: "3"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 40, y: 100, width: 60, height: 30), label: "Setup"),
            ]
        )

        let answer = try Self.answer(for: [container])

        #expect(answer.text.contains("Step 3 of 4, Setup · Other (2 texts inside) · 16,100 311×30"))
        #expect(!answer.text.contains("StaticText"))
    }

    /// Images and texts are counted together, singular and plural.
    @Test
    func imagesAndTextsAreCountedTogether() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "Rated 4, Good",
            children: [
                AXNode(type: "Image", frame: AXNode.Frame(x: 16, y: 100, width: 20, height: 30), label: "Star"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 40, y: 100, width: 20, height: 30), label: "4"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 60, y: 100, width: 60, height: 30), label: "Good"),
            ]
        )

        let answer = try Self.answer(for: [container])

        #expect(answer.text.contains("Other (1 image, 2 texts inside)"))
    }

    /// A text the label lacks makes the node list child by child, as before.
    @Test
    func aContainerHoldingATextItsLabelLacksListsChildByChild() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 60),
            label: "Order",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 100, height: 30), label: "Order"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 130, width: 100, height: 30), label: "Delivered Tuesday"),
            ]
        )

        let answer = try Self.answer(for: [container])

        #expect(answer.text.contains("Delivered Tuesday · StaticText"))
        #expect(!answer.text.contains("inside)"))
    }

    /// An enabled control below keeps the node child by child.
    @Test
    func anEnabledControlBelowKeepsTheListing() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "Favourites",
            children: [AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 100, width: 40, height: 30), label: "Favourites")]
        )

        let answer = try Self.answer(for: [container, AXNode(type: "Image", frame: AXNode.Frame(x: 0, y: 300, width: 10, height: 10), label: "Spare")])

        #expect(!answer.text.contains("inside)"))
    }

    /// `--match` finds a folded image and says whose row it is in.
    @Test
    func matchListsAFoldedDescendantWithItsRow() throws {
        let answer = try Self.answer(for: [Self.stars()], match: "Favourite")

        #expect(answer.text.contains("Favourite · Image · 16,100 20×30 (inside '8 stars')"))
        #expect(!answer.text.contains("8 stars · Other"))
        #expect(answer.text.contains("8 inside a folded row (listed)"))
    }

    /// The delta path reads the unfolded elements, so a child image removed is still seen.
    @Test
    func aScreenDeltaStillSeesTheFoldedImages() {
        let before = Self.screen(children: [Self.stars()])
        let after = Self.screen(children: [Self.stars(images: 7)])

        let delta = ScreenDelta(from: before, to: after)

        #expect(delta.disappearedCount == 1)
        #expect(delta.disappeared.first?.contains("Favourite · Image") == true)
    }

    /// A disabled `Button` restating its `Other` row keeps collapsing into it as unfolded, so the folded row takes the Button's type.
    @Test
    func aRestatingDescendantGivesTheFoldedRowItsMoreSpecificType() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "Settings",
            children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 100, width: 200, height: 30), label: "Settings", isEnabled: false),
                AXNode(type: "Image", frame: AXNode.Frame(x: 220, y: 100, width: 20, height: 30), label: "Chevron"),
            ]
        )

        let answer = try Self.answer(for: [container])

        #expect(answer.text.contains("Settings · Button (1 image inside) · 16,100 200×30"))
    }

    /// Only leaves are counted: an intermediate container and a nested restater are not texts of their own.
    @Test
    func onlyLeafTextsAreCounted() throws {
        let container = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "Step 3 of 4, Setup",
            children: [
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 40, y: 100, width: 60, height: 30),
                    label: "Setup",
                    children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 40, y: 100, width: 60, height: 30), label: "Setup")]
                ),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 20, height: 30), label: "Step 3 of 4"),
            ]
        )

        let answer = try Self.answer(for: [container])

        #expect(answer.text.contains("Other (2 texts inside)"))
    }

    private static func stars(images: Int = 8) -> AXNode {
        AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 100, width: 311, height: 30),
            label: "8 stars",
            children: (0 ..< images).map { index in
                AXNode(type: "Image", frame: AXNode.Frame(x: 16 + Double(index) * 21, y: 100, width: 20, height: 30), label: "Favourite")
            }
        )
    }

    private static func screen(children: [AXNode]) -> AXNode {
        AXNode(
            type: "Application",
            frame: ScreenTreeFixture.screenFrame,
            label: "Example",
            children: [AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, identifier: "Screen", children: children)]
        )
    }

    private static func answer(for children: [AXNode], match: String? = nil) throws -> Answer {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "screen", captures: [
                CaptureBundleFixture.Capture(screenID: "screen", state: Walkbook.CaptureState(theme: .light), tree: screen(children: children)),
            ]),
        ])
        return try BundleScreenQuery(bundle).answer(step: "1", match: match)
    }
}
