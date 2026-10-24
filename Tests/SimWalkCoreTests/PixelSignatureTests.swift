//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import Testing

/// The pixel signature a screen with no text is hashed and compared by (SimWalk#150).
struct PixelSignatureTests {
    static var note: String {
        "(the tree has no text, so the screen hash includes a pixel hash)"
    }

    @Test
    func identicalImagesHaveNoChangedCellsAndTheSameHashToken() throws {
        let a = try Self.signature(Self.png())
        let b = try Self.signature(Self.png())

        #expect(a.changedFraction(to: b) == 0)
        #expect(a.hashToken == b.hashToken)
        #expect(a.columns == 16)
        #expect(a.rows == 35)
    }

    @Test
    func aWhiteTopHalfChangesAboutHalfTheCellsAndTheToken() throws {
        let black = try Self.signature(Self.png())
        let half = try Self.signature(Self.png(whiteTopFraction: 0.5))

        #expect(abs(black.changedFraction(to: half) - 0.5) < 0.05)
        #expect(black.hashToken != half.hashToken)
    }

    @Test
    func aChangeThatKeepsEveryCellInItsLevelLeavesTheHashToken() throws {
        let black = try Self.signature(Self.png())
        let noisy = try Self.signature(Self.png(lineGrey: 100))

        #expect(black.hashToken == noisy.hashToken)
    }

    @Test
    func aTurnedScreenIsEntirelyChanged() throws {
        let portrait = try Self.signature(Self.png())
        let landscape = try Self.signature(Self.png(width: 844, height: 390))

        #expect(landscape.rows == 7)
        #expect(portrait.changedFraction(to: landscape) == 1)
    }

    @Test
    func bytesThatAreNotAnImageHaveNoSignature() {
        #expect(PixelSignature(png: Data("not a png".utf8)) == nil)
        #expect(PixelSignature(png: Data()) == nil)
    }

    @Test
    func theSignatureIsNeededOnlyWhenTheTreeListsNoText() {
        let frame = AXNode.Frame(x: 0, y: 0, width: 390, height: 844)
        let empty = AXNode(type: "Application", frame: frame)
        let unlabelled = AXNode(type: "Application", frame: frame, children: [AXNode(type: "Other", frame: frame, children: [AXNode(type: "Other", frame: frame)])])
        let labelled = AXNode(type: "Application", frame: frame, children: [AXNode(type: "StaticText", frame: frame, label: "Score")])

        #expect(PixelSignature.isNeeded(for: empty))
        #expect(PixelSignature.isNeeded(for: unlabelled))
        #expect(!PixelSignature.isNeeded(for: labelled))
    }

    @Test
    func theScreenHashIsUnchangedWithoutPixelsAndMovesWithThemOnATextlessTree() throws {
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 390, height: 844))
        let black = try Self.signature(Self.png())
        let half = try Self.signature(Self.png(whiteTopFraction: 0.5))

        #expect(ScreenHash.of(tree, pixels: nil) == ScreenHash.of(tree))
        #expect(ScreenHash.of(tree, pixels: black) != ScreenHash.of(tree))
        #expect(ScreenHash.of(tree, pixels: black) != ScreenHash.of(tree, pixels: half))
        #expect(ScreenHash.of(tree, pixels: black) == ScreenHash.of(tree, pixels: black))
    }

    @Test
    func theDeltaReportsHowMuchOfThePictureChanged() {
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 390, height: 844))
        let cells = [UInt8](repeating: 0, count: 100)
        let before = PixelSignature(columns: 10, rows: 10, cells: cells)
        func moved(_ count: Int) -> PixelSignature {
            PixelSignature(columns: 10, rows: 10, cells: [UInt8](repeating: 0, count: 100 - count) + [UInt8](repeating: 255, count: count))
        }

        let most = ScreenDelta(from: tree, to: tree, pixels: (before, moved(71)))
        #expect(most.pixelsChanged == 0.71)
        #expect(most.residue == ["delta: nothing appeared or disappeared", "pixels: 71% of the screen changed \(Self.note)"])
        let none = ScreenDelta(from: tree, to: tree, pixels: (before, before))
        #expect(none.residue == ["delta: nothing appeared or disappeared", "pixels: nothing changed \(Self.note)"])
        let small = ScreenDelta(from: tree, to: tree, pixels: (PixelSignature(columns: 25, rows: 10, cells: [UInt8](repeating: 0, count: 250)), PixelSignature(columns: 25, rows: 10, cells: [UInt8](repeating: 255, count: 1) + [UInt8](repeating: 0, count: 249))))
        #expect(small.pixelsChanged == 0.004)
        #expect(small.residue.last == "pixels: less than 1% of the screen changed \(Self.note)")
        #expect(ScreenDelta(from: tree, to: tree).residue == ["delta: nothing appeared or disappeared"])
    }

    @Test
    func aPixelsLineSitsRightAfterTheFirstDeltaLine() {
        let before = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 1, height: 1))
        let after = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 1, height: 1), children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 0, width: 1, height: 1), label: "Hi")])
        let grid = PixelSignature(columns: 1, rows: 1, cells: [0])

        let residue = ScreenDelta(from: before, to: after, pixels: (grid, grid)).residue

        #expect(residue.prefix(2) == ["delta: 1 appeared, 0 disappeared", "pixels: nothing changed \(Self.note)"])
        #expect(residue.count == 3)
    }

    @Test
    func aDeltaWrittenBeforeThePixelsWereAddedStillDecodes() throws {
        let json = #"{"appearedCount":0,"disappearedCount":0,"appeared":[],"disappeared":[]}"#

        let delta = try JSONDecoder().decode(ScreenDelta.self, from: Data(json.utf8))

        #expect(delta.pixelsChanged == nil)
        #expect(delta.residue == ["delta: nothing appeared or disappeared"])
    }
}

extension PixelSignatureTests {
    static func signature(_ png: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> PixelSignature {
        try #require(PixelSignature(png: png), sourceLocation: sourceLocation)
    }

    /// A black PNG, optionally with the top `whiteTopFraction` white or a one-pixel vertical line of grey `lineGrey`.
    static func png(width: Int = 390, height: Int = 844, whiteTopFraction: Double = 0, lineGrey: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), sourceLocation: sourceLocation)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if whiteTopFraction > 0 {
            let band = (Double(height) * whiteTopFraction).rounded()
            context.setFillColor(gray: 1, alpha: 1)
            // CoreGraphics' origin is bottom-left, so the top of the picture is the high y.
            context.fill(CGRect(x: 0, y: Double(height) - band, width: Double(width), height: band))
        }
        if let lineGrey {
            context.setFillColor(gray: CGFloat(lineGrey) / 255, alpha: 1)
            context.fill(CGRect(x: 100, y: 0, width: 1, height: height))
        }
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil), sourceLocation: sourceLocation)
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return data as Data
    }
}
