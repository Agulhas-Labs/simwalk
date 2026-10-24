//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO

/// A screenshot turned a quarter so its stored pixels are the way up the app is drawn (SimWalk#221).
///
/// **Why the stored pixels, not the tag.** A device turned to landscape hands back a screen image in its portrait pixel grid with the content drawn sideways, and an `eXIf` Orientation tag (8 measured on an iPad mini) that says how to turn it. Nothing downstream honours the tag: the brightness, the pixel signature and a person opening `screen.png` in a tool that ignores it all read the stored grid. So the picture is drawn rotated into a context of swapped width and height, and the PNG written has no orientation tag at all. The source is decoded by `CGImageSourceCreateImageAtIndex`, which ignores the tag, so a tagged input is turned from its stored pixels, which is the point.
///
/// **CoreGraphics in the core is the deliberate exception ``ScreenshotBrightness`` explains**: the turn is reachable by `swift test` here, where inside the XCUITest runner nothing could reach it.
public struct UprightScreenshot {
    /// The PNG with its stored pixels turned by `turn` and no orientation tag; `nil` when the bytes are not an image this platform can decode or draw.
    public static func png(_ data: Data, turned turn: QuarterTurn) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        let width = image.width
        let height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = image.colorSpace.flatMap {
            CGContext(data: nil, width: height, height: width, bitsPerComponent: 8, bytesPerRow: 0, space: $0, bitmapInfo: bitmapInfo)
        } ?? CGContext(data: nil, width: height, height: width, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)
        guard let context else {
            return nil
        }
        // CoreGraphics' origin is bottom-left: clockwise maps (x, y) to (y, width - x), counter-clockwise to (height - y, x).
        switch turn {
        case .clockwise:
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        case .counterClockwise:
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let turned = context.makeImage() else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, turned, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

public extension UprightScreenshot {
    /// A quarter turn, as the viewer sees the picture move.
    enum QuarterTurn: Sendable {
        case clockwise
        case counterClockwise
    }
}
