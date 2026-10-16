//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// What an answer claims to have saved, which is the one figure in this tool that flatters it — so every constant behind it is pinned against a real artefact and every direction it could be wrong in is asserted.
struct ContextSavingTests {
    /// The size a real walk of an iPhone 17 produces, its long edge over the cap, so the scaling is exercised by the shape the tool actually meets.
    ///
    /// 1206 × 2622 scales by 2576/2622 and comes to 4,069.5 tiles, which is 4,070 — a fraction of a tile is still a tile. The intermediate edges are deliberately *not* rounded to integers first: 1185 × 2576 lands on 4,071 and 1184 × 2576 on 4,067, so rounding early is a different arithmetic wearing the same constants.
    @Test
    func ascreenshotOverTheCapIsPricedFromItsScaledArea() {
        #expect(ImageTokenEstimate.tokens(width: 1206, height: 2622) == 4070)
    }

    /// The long edge is the long edge whichever way round the picture is — a landscape capture of the same screen costs the same as the portrait one.
    @Test
    func alandscapeScreenshotIsPricedByItsLongEdgeToo() {
        #expect(ImageTokenEstimate.tokens(width: 2622, height: 1206) == 4070)
        #expect(ImageTokenEstimate.tokens(width: 2622, height: 1206) == ImageTokenEstimate.tokens(width: 1206, height: 2622))
    }

    /// An image inside the cap is not scaled at all, so its price is its own area over the tile size — 300 × 300 is exactly 120 tiles, with nothing to round.
    @Test
    func ascreenshotInsideTheCapIsPricedFromItsOwnArea() {
        #expect(ImageTokenEstimate.tokens(width: 300, height: 300) == 120)
    }

    /// One pixel is a fraction of one tile, and a fraction of a tile is charged as a tile — an image that costs something must never price as free.
    @Test
    func theSmallestImageStillCostsAWholeTile() {
        #expect(ImageTokenEstimate.tokens(width: 1, height: 1) == 1)
    }

    /// A size that is not a size prices as nothing rather than as a negative or a trap.
    @Test(arguments: [(0, 100), (100, 0), (-4, -4)])
    func asizeThatIsNotAsizePricesAsNothing(_ size: (width: Int, height: Int)) {
        #expect(ImageTokenEstimate.tokens(width: size.width, height: size.height) == 0)
    }

    /// The dimensions come off the PNG's own header, so a bundle's screenshots are weighed without decoding a megabyte of pixels to learn two integers.
    @Test
    func apngsSizeIsReadFromItsHeader() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("shot.png")
        try CaptureBundleFixture.screenshot(width: 1206, height: 2622).write(to: url)

        #expect(PNGSize(contentsOf: url) == PNGSize(width: 1206, height: 2622))
    }

    /// Anything that is not a PNG this understands answers nothing at all, and the weighing leaves it out — which keeps the figure a floor instead of guessing a size for a file it could not read.
    @Test(arguments: ["", "png", "\u{89}PNG-but-not-really"])
    func bytesThatAreNotApngHeaderAnswerNothing(_ contents: String) throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("shot.png")
        try Data(contents.utf8).write(to: url)

        #expect(PNGSize(contentsOf: url) == nil)
        #expect(PNGSize(header: Data(contents.utf8)) == nil)
    }

    /// A bundle whose artefacts are not on disk weighs nothing, and an answer over it says nothing about a saving — an absence and a saving of zero are different claims, and only the first is true.
    @Test
    func abundleWithNothingToWeighIsNotAsavingOfZero() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/nowhere.simwalk"), manifest: CaptureBundleTests.manifest())

        #expect(ContextSaving.weighing(bundle) == nil)
    }

    /// An answer longer than what it stood in for saved nothing; it did not save a negative amount, and the line says so in words rather than in a minus sign.
    @Test
    func ananswerThatCostMoreThanItReplacedSavesNothingRatherThanANegativeAmount() {
        let saving = ContextSaving(screenshotTokens: [], treeBytes: 400, servedBytes: 40000)

        #expect(saving.savedTokens == 0)
        #expect(saving.line.hasPrefix("no tokens saved — "))
    }

    /// Both halves of the arithmetic ride beside the figure: the pixel cap for the screenshots, the byte ratio for the trees, and what the answer itself cost.
    @Test
    func thecontextLineCarriesTheArithmeticForEachHalf() {
        let saving = ContextSaving(screenshotTokens: [4070, 4070, 4070], treeBytes: 43890, servedBytes: 718)

        #expect(saving.replacedTokens == 3 * 4070 + 43890 / 4)
        #expect(saving.line == "~23k tokens saved — 3 screenshots (~4.1k each at the 2576 px cap) and 43 kB of accessibility trees at 4 bytes a token, against 718 B served. A floor: only what this answer stood in for is counted.")
    }

    /// A weighing with no tree — every `bundle screen` answer — still converts its served bytes to tokens, so the byte ratio rides beside the served figure instead of vanishing with the trees clause that used to carry it (SimWalk#20 round 3, finding 5).
    @Test
    func theByteRatioIsStatedWheneverServedBytesAreConvertedEvenWithNoTree() {
        let saving = ContextSaving(screenshotTokens: [4070], treeBytes: 0, servedBytes: 4300)

        #expect(saving.savedTokens == 4070 - 4300 / 4)
        #expect(saving.line == "~3.0k tokens saved — 1 screenshot (~4.1k at the 2576 px cap), against 4.3 kB served at 4 bytes a token. A floor: only what this answer stood in for is counted.")
    }

    /// "Each" is a claim about every one of them, so it is made only when they are in fact alike — a bundle of differently-sized captures is given a total instead.
    @Test
    func screenshotsOfDifferentSizesAreTotalledRatherThanClaimedToBeAlike() {
        let saving = ContextSaving(screenshotTokens: [4070, 120], treeBytes: 0, servedBytes: 100)

        #expect(saving.line.contains("2 screenshots (~4.2k in total at the 2576 px cap)"))
        // Nothing that weighed nothing is printed as a heading over nothing.
        #expect(!saving.line.contains("accessibility trees"))
    }

    /// A bundle on disk is weighed as a reader would find it: every screenshot by its pixels, every tree by its bytes.
    @Test
    func abundleOnDiskIsWeighedCaptureByCapture() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: CaptureBundleFixture.plainScreen()),
        ])

        let saving = try #require(ContextSaving.weighing(bundle))

        #expect(saving.screenshotTokens == [4070, 4070])
        #expect(saving.treeBytes > 0)
    }

    /// `bundle screen` reads one capture, not a bundle's worth, and pricing it against every screenshot the bundle holds would claim a saving on captures it never opened — and its tree is left out entirely, not merely divided down, because a reader answering a text question opens the screenshot or reads the tree, never both (SimWalk#20 round 2, finding 2).
    @Test
    func aonecaptureWeighingPricesTheScreenshotAloneNeverTheTree() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: CaptureBundleFixture.plainScreen()),
        ])
        let lightCapture = try #require(bundle.manifest.screens.first?.captures.first)

        let saving = try #require(ContextSaving.weighing(bundle, capture: lightCapture))

        #expect(saving.screenshotTokens == [4070])
        #expect(saving.treeBytes == 0)
    }

    /// A capture whose artefacts never made it to disk weighs nothing on its own, the same floor rule as the whole-bundle weighing.
    @Test
    func aonecaptureWeighingAnswersNilWhenThatCapturesArtefactsAreNotOnDisk() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])
        let ghost = CaptureManifest.StateCapture(screenID: "ghost", state: Walkbook.CaptureState(theme: .light))

        #expect(ContextSaving.weighing(bundle, capture: ghost) == nil)
    }

    /// Sizes are read on the SI ladder Sift prints, not on a 1024-based one — the two tools' answers are read in one session by one reader, and `43 kB` meaning two things is a divergence nobody would think to check for.
    @Test
    func sizesAreReadOnTheSameLadderTheSiblingToolPrints() {
        #expect(ByteSize.short(1_003_000) == "1.0 MB")
        #expect(ByteSize.short(43890) == "43 kB")
        #expect(ByteSize.short(700) == "700 B")
        #expect(ByteSize.short(4321) == "4.3 kB")
    }

    /// The log records totals rather than each screenshot, so the subtraction it can reconstruct has to be the same one the answer printed.
    @Test
    func alogsTotalsPriceAcallExactlyAsItsAnswerDid() {
        let saving = ContextSaving(screenshotTokens: [4070, 4070, 4070], treeBytes: 43890, servedBytes: 718)

        #expect(ContextSaving.saved(imageTokens: 3 * 4070, treeBytes: 43890, servedBytes: 718) == saving.savedTokens)
    }
}
