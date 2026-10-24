//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `ScreenshotFit` against a synthetic 3× screenshot with one red rectangle at a known point position (SimWalk#200).
struct ScreenshotFitTests {
    /// The rectangle's frame in points, and the screen it sits on.
    static let button = AXNode.Frame(x: 100, y: 300, width: 60, height: 30)

    static func tree(extra: [AXNode] = []) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            AXNode(type: "Button", frame: button, label: "Save"),
        ] + extra)
    }

    /// A white image of `width` × `height` px in `space` (sRGB unless named) with the button's rectangle in that space's full red at `factor` pixels per point.
    static func png(
        width: Int = 1206, height: Int = 2622, factor: Double = 3, space name: CFString = CGColorSpace.sRGB,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Data {
        let space = try #require(CGColorSpace(name: name), sourceLocation: sourceLocation)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), sourceLocation: sourceLocation)
        try context.setFillColor(#require(CGColor(colorSpace: space, components: [1, 1, 1, 1]), sourceLocation: sourceLocation))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        try context.setFillColor(#require(CGColor(colorSpace: space, components: [1, 0, 0, 1]), sourceLocation: sourceLocation))
        // CoreGraphics draws from the bottom-left; the tree's frames are from the top-left.
        context.fill(CGRect(
            x: button.x * factor, y: Double(height) - (button.y + button.height) * factor,
            width: button.width * factor, height: button.height * factor
        ))
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil), sourceLocation: sourceLocation)
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return data as Data
    }

    /// The pixel at `x`, `y` (from the top-left) of the PNG at `url`, read in the image's own colour space so no conversion moves it, with the image's size and the name of that space.
    static func pixel(at url: URL, x: Int, y: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> Pixel {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), sourceLocation: sourceLocation)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), sourceLocation: sourceLocation)
        let space = try #require(image.colorSpace, sourceLocation: sourceLocation)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), sourceLocation: sourceLocation)
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Pixel(red: bytes[0], green: bytes[1], width: image.width, height: image.height, space: space.name as String?)
    }

    static func request(scale: Int = 1, of label: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> ScreenshotFit.Request {
        try #require(ScreenshotFit.Request(scale: scale, label: label), sourceLocation: sourceLocation)
    }

    /// (a) The default is one pixel per point, and the rectangle is where the tree's frame says.
    @Test
    func pointScaleWritesTheRootFrameSizeWithTheRectangleWhereTheTreeSaysIt() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "a.png")

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(), request: Self.request(), to: url)

        #expect(outcome == .written(path: url.path, width: 402, height: 874, scale: 1, label: nil))
        let centre = try Self.pixel(at: url, x: 130, y: 315)
        #expect(centre.red == 255 && centre.green == 0)
        let outside = try Self.pixel(at: url, x: 130, y: 340)
        #expect(outside.green == 255)
    }

    /// A Display P3 screenshot keeps its space and its colours: its full red, outside sRGB, is still full red, not clipped or shifted into another space.
    @Test
    func aDisplayP3ScreenshotKeepsItsColourSpaceAndItsColours() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "p3.png")

        _ = try ScreenshotFit.write(png: Self.png(space: CGColorSpace.displayP3), tree: Self.tree(), request: Self.request(), to: url)

        let centre = try Self.pixel(at: url, x: 130, y: 315)

        #expect(centre.space == CGColorSpace.displayP3 as String)
        #expect(centre.red == 255 && centre.green == 0)
    }

    /// (b) Scale 3 keeps the runner's pixels.
    @Test
    func scaleThreeWritesThreePixelsPerPoint() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "b.png")

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(), request: Self.request(scale: 3), to: url)

        #expect(outcome == .written(path: url.path, width: 1206, height: 2622, scale: 3, label: nil))
        #expect(try Self.pixel(at: url, x: 390, y: 945).red > 200)
    }

    /// Two exact `Save` buttons tie at the top rank, so nothing is written and the line says to name one, rather than cropping the first.
    @Test
    func aLabelTwoElementsCarryEquallyWritesNothing() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "tie.png")
        let other = AXNode(type: "Button", frame: AXNode.Frame(x: 200, y: 500, width: 60, height: 30), label: "Save")

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(extra: [other]), request: Self.request(of: "Save"), to: url)

        #expect(outcome == .refused("2 elements carry 'Save' equally; name one by its identifier"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// SimWalk#218: two separate elements with one label at one frame, neither inside the other, are one element to crop, not a tie.
    @Test
    func twoSiblingsWithOneLabelAtOneFrameAreOneElementNotATie() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "siblings.png")
        let twin = AXNode(type: "Button", frame: Self.button, label: "Save")

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(extra: [twin]), request: Self.request(of: "Save"), to: url)

        #expect(outcome == .written(path: url.path, width: 76, height: 46, scale: 1, label: "Save"))
    }

    /// A cell and the button inset in it carrying one label at one spot are one control, so the crop is written around it; the same label at two different spots still refuses (SimWalk#214).
    @Test
    func aCellAndItsInsetButtonAtOneSpotAreOneElementButTwoSpotsStillTie() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "wrapper.png")
        let root = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let wrapper = AXNode(type: "Cell", frame: AXNode.Frame(x: 90, y: 290, width: 80, height: 50), label: "Save", children: [
            AXNode(type: "Button", frame: Self.button, label: "Save"),
        ])

        let one = try ScreenshotFit.write(png: Self.png(), tree: AXNode(type: "Application", frame: root, children: [wrapper]), request: Self.request(of: "Save"), to: url)

        #expect(one == .written(path: url.path, width: 96, height: 66, scale: 1, label: "Save"))

        let elsewhere = AXNode(type: "Button", frame: AXNode.Frame(x: 200, y: 500, width: 60, height: 30), label: "Save")
        let two = try ScreenshotFit.write(png: Self.png(), tree: AXNode(type: "Application", frame: root, children: [wrapper, elsewhere]), request: Self.request(of: "Save"), to: url)

        #expect(two == .refused("2 elements carry 'Save' equally; name one by its identifier"))
    }

    /// (c) A crop is the element's frame plus 8 pt, so 76 × 46 px, and its centre is the rectangle.
    @Test
    func aCropIsTheElementPlusEightPoints() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "c.png")

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(), request: Self.request(of: "Save"), to: url)

        #expect(outcome == .written(path: url.path, width: 76, height: 46, scale: 1, label: "Save"))
        let centre = try Self.pixel(at: url, x: 38, y: 23)
        #expect(centre.red > 200 && centre.green < 80)
        #expect(try Self.pixel(at: url, x: 2, y: 2).green > 200)
    }

    /// (c) A crop at the screen's edge is clipped rather than padded.
    @Test
    func aCropNearTheEdgeIsClippedToTheScreen() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "edge.png")
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 3, y: 4, width: 60, height: 30), label: "Back"),
        ])

        let outcome = try ScreenshotFit.write(png: Self.png(), tree: tree, request: Self.request(of: "Back"), to: url)

        #expect(outcome == .written(path: url.path, width: 71, height: 42, scale: 1, label: "Back"))
    }

    /// (d) A label nothing carries, or two elements carry equally, writes nothing.
    @Test
    func anUnknownOrAmbiguousLabelIsRefusedAndWritesNothing() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "d.png")
        let lead = { (label: String, y: Double) in
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 10, y: y, width: 100, height: 20), label: label)
        }
        let tree = Self.tree(extra: [lead("Sail, 12 August 14:50 · 3.43 km", 500), lead("Sail, 12 August 16:10 · 5.10 km", 540)])

        let unknown = try ScreenshotFit.write(png: Self.png(), tree: Self.tree(), request: Self.request(of: "Cancel"), to: url)
        let ambiguous = try ScreenshotFit.write(png: Self.png(), tree: tree, request: Self.request(of: "Sail, 12 August"), to: url)

        #expect(unknown == .refused("no element labelled 'Cancel' on the screen read"))
        #expect(ambiguous == .refused("'Sail, 12 August' matches 2 elements on the screen read"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// (e) An image of another shape than the screen is refused, naming both sizes.
    @Test
    func anImageOfAnotherShapeIsRefusedAndWritesNothing() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "e.png")

        let outcome = try ScreenshotFit.write(png: Self.png(width: 2622, height: 1206), tree: Self.tree(), request: Self.request(), to: url)

        #expect(outcome == .refused("the screenshot is 2622×1206 px and the screen read is 402×874 pt: their shapes differ"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A request's scale is 1…3.
    @Test
    func aScaleOutsideOneToThreeIsNotARequest() {
        #expect(ScreenshotFit.Request(scale: 0) == nil)
        #expect(ScreenshotFit.Request(scale: 4) == nil)
    }

    /// (f) The one line for each outcome.
    @Test
    func theLineNamesThePathTheSizeAndThePrice() {
        #expect(ScreenshotFit.line(.written(path: "/t/s.png", width: 402, height: 874, scale: 1, label: nil))
            == "screenshot: /t/s.png (402×874 px, point scale, about 469 tokens to view)")
        #expect(ScreenshotFit.line(.written(path: "/t/s.png", width: 1206, height: 2622, scale: 3, label: nil))
            == "screenshot: /t/s.png (1206×2622 px, 3× point scale, about 4,070 tokens to view)")
        #expect(ScreenshotFit.line(.written(path: "/t/s.png", width: 804, height: 1748, scale: 2, label: nil))
            == "screenshot: /t/s.png (804×1748 px, 2× point scale, about 1,874 tokens to view)")
        #expect(ScreenshotFit.line(.written(path: "/t/s.png", width: 406, height: 136, scale: 1, label: "Save"))
            == "screenshot: /t/s.png (406×136 px, point scale, 'Save' + 8 pt, about 74 tokens to view)")
        #expect(ScreenshotFit.line(.refused("no element labelled 'X' on the screen read"))
            == "screenshot: not written — no element labelled 'X' on the screen read")
    }
}

extension ScreenshotFitTests {
    struct Pixel {
        let red: UInt8
        let green: UInt8
        let width: Int
        let height: Int
        let space: String?
    }
}
