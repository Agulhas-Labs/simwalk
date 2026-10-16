//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import Testing
import UniformTypeIdentifiers

/// The measurement `StateApplicationCheck` rests its appearance half on, checked against pictures whose answer is known before it is asked.
struct ScreenshotBrightnessTests {
    @Test(arguments: [(1.0, 1.0), (0.0, 0.0), (0.5, 0.5)])
    func asolidGreyMeasuresAsItsOwnBrightness(_ white: Double, _ expected: Double) throws {
        let measured = try #require(try ScreenshotBrightness.mean(ofPNG: Self.png(red: white, green: white, blue: white)))

        #expect(abs(measured - expected) < 0.01)
    }

    /// Weighted the way an eye weights brightness rather than averaged flat.
    ///
    /// A green screen and a blue one of the same numeric value are not equally bright to look at, and a check about darkness has to agree with the eye — so the Rec 709 coefficients are the measurement, not a flat mean of three channels.
    @Test
    func brightnessIsWeightedTheWayTheEyeWeightsIt() throws {
        let green = try #require(try ScreenshotBrightness.mean(ofPNG: Self.png(red: 0, green: 1, blue: 0)))
        let blue = try #require(try ScreenshotBrightness.mean(ofPNG: Self.png(red: 0, green: 0, blue: 1)))

        #expect(green > blue)
        #expect(abs(green - 0.7152) < 0.01)
        #expect(abs(blue - 0.0722) < 0.01)
    }

    /// Half the picture black and half white averages to the middle — which is the property that makes this a measurement of a *screen* rather than of whatever pixel it happened to sample.
    @Test
    func themeasurementIsTheMeanOfTheWholePictureRatherThanOnePixel() throws {
        let measured = try #require(try ScreenshotBrightness.mean(ofPNG: Self.halfAndHalf()))

        #expect(abs(measured - 0.5) < 0.02)
    }

    /// Bytes that are not an image have produced no measurement, and standing in a zero would make an unreadable capture the darkest thing in any comparison.
    @Test
    func bytesThatAreNotAnImageMeasureNothing() {
        #expect(ScreenshotBrightness.mean(ofPNG: Data("not a picture".utf8)) == nil)
        #expect(ScreenshotBrightness.mean(ofPNG: Data()) == nil)
    }

    private static func png(red: Double, green: Double, blue: Double, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        try encode(sourceLocation: sourceLocation) { context in
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private static func halfAndHalf(sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        try encode(sourceLocation: sourceLocation) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        }
    }

    private static func encode(sourceLocation: SourceLocation, drawing: (CGContext) -> Void) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            sourceLocation: sourceLocation
        )
        drawing(context)
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let encoded = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil),
            sourceLocation: sourceLocation
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return encoded as Data
    }
}
