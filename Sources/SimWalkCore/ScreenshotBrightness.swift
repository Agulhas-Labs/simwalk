//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO

/// The mean brightness of a screenshot, which is the one measurement that separates a dark render from a light one.
///
/// **The byte comparison is not enough on its own, measured.** A walk of a real app's Browse screen on 2026-08-20 produced a `light` and a `dark` capture that differ by 41 bytes in 249 KB — the status-bar clock, and nothing else. Both are light: mean colour `(238, 237, 234)` in each, to the byte. So `screens/browse/dark/` holds a light render, outcome `captured`, and the byte check that catches this on a still clock says nothing about it here. A clock ticking between two shots is enough to defeat identity, so the check that survives it has to measure the picture rather than compare the file.
///
/// **CoreGraphics in the core is a deliberate exception, not a drift.** `AXNode.Frame` is four `Double`s precisely so the core stays free of it — but that rule is about the *JSON shape* staying obvious to a reader, and this decodes a PNG rather than describing one. It ships on every Apple platform the package builds for, so nothing about portability changes; what changes is that the measurement is reachable by `swift test`, where the same twenty lines inside the XCUITest runner would have been unreachable by anything.
public struct ScreenshotBrightness {
    /// The screenshot's mean brightness in 0…1, or `nil` when the bytes are not an image this platform can decode.
    ///
    /// **This is luma, not relative luminance**, and the distinction is worth stating rather than blurring: the Rec 709 coefficients are applied to the *gamma-encoded* sRGB channels the PNG stores, where relative luminance is defined over linearised ones. Linearising was considered and left: the decision resting on this compares two captures of the same screen with each other, so it needs the measurement to be monotonic in brightness and not to be on any particular scale — and linearising would move every number, including the one the margin was measured against, for no change in any answer.
    ///
    /// Averaged by drawing the whole image into a single pixel at high interpolation quality, which is the mean the graphics stack computes for a downscale — considerably faster than summing three million pixels and, at 8 bits a channel, the same answer. `nil` rather than a default: a screenshot that cannot be read has produced no measurement, and standing in a zero would make an unreadable capture the darkest thing in any comparison.
    public static func mean(ofPNG data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Rec. 709 coefficients — the weighting the eye actually applies, so a green screen and a blue
        // one of the same numeric value are not called equally bright.
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }
}
