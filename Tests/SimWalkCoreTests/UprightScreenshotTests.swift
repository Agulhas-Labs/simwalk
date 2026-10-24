//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import Testing

/// The turn that puts a landscape screenshot's stored pixels upright (SimWalk#221).
struct UprightScreenshotTests {
    /// The fixture is 4 wide and 2 high: red at the top-left pixel, blue at the bottom-right, the rest white.
    @Test
    func clockwiseMovesTheTopLeftToTheTopRightAndSwapsTheSize() throws {
        let turned = try #require(UprightScreenshot.png(Self.marked(), turned: .clockwise))
        let grid = try Self.grid(of: turned)

        #expect(grid.width == 2)
        #expect(grid.height == 4)
        #expect(grid.pixel(1, 0) == .red)
        #expect(grid.pixel(0, 3) == .blue)
        #expect(grid.pixel(0, 0) == .white)
    }

    @Test
    func counterClockwiseMovesTheTopLeftToTheBottomLeftAndSwapsTheSize() throws {
        let turned = try #require(UprightScreenshot.png(Self.marked(), turned: .counterClockwise))
        let grid = try Self.grid(of: turned)

        #expect(grid.width == 2)
        #expect(grid.height == 4)
        #expect(grid.pixel(0, 3) == .red)
        #expect(grid.pixel(1, 0) == .blue)
        #expect(grid.pixel(0, 0) == .white)
    }

    @Test
    func theOutputCarriesNoOrientationTag() throws {
        for turn in [UprightScreenshot.QuarterTurn.clockwise, .counterClockwise] {
            let turned = try #require(UprightScreenshot.png(Self.marked(orientation: 8), turned: turn))

            #expect(try Self.orientation(of: turned) == nil)
        }
    }

    @Test
    func anInputTaggedEightIsTurnedFromItsStoredPixels() throws {
        let tagged = try Self.marked(orientation: 8)
        #expect(try Self.orientation(of: tagged) == 8)

        let turned = try #require(UprightScreenshot.png(tagged, turned: .clockwise))
        let grid = try Self.grid(of: turned)

        #expect(grid.width == 2)
        #expect(grid.pixel(1, 0) == .red)
    }

    @Test
    func bytesThatAreNotAnImageAreNotTurned() {
        #expect(UprightScreenshot.png(Data([1, 2, 3]), turned: .clockwise) == nil)
    }

    // MARK: - Fixtures

    static func marked(orientation: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), sourceLocation: sourceLocation)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        // CoreGraphics' origin is bottom-left: the top-left pixel is (0, 1).
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 3, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil), sourceLocation: sourceLocation)
        let properties: [CFString: Any]? = orientation.map { [kCGImagePropertyOrientation: $0] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return data as Data
    }

    static func orientation(of png: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> Int? {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil), sourceLocation: sourceLocation)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyOrientation] as? Int
    }

    static func grid(of png: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> Grid {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil), sourceLocation: sourceLocation)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), sourceLocation: sourceLocation)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), sourceLocation: sourceLocation)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Grid(width: image.width, height: image.height, bytes: bytes)
    }
}

extension UprightScreenshotTests {
    enum Colour: Equatable {
        case red, blue, white, other
    }

    struct Grid {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// The pixel at column `x`, row `y` counted from the top.
        func pixel(_ x: Int, _ y: Int) -> Colour {
            let offset = (y * width + x) * 4
            return switch (bytes[offset], bytes[offset + 1], bytes[offset + 2]) {
            case (255, 0, 0): .red
            case (0, 0, 255): .blue
            case (255, 255, 255): .white
            default: .other
            }
        }
    }
}
