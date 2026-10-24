//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO

/// Fits the runner's screenshot to the question a read was asked, so the agent is handed a file priced for it (SimWalk#200).
///
/// The runner sends the app's PNG in device pixels, which is the most the agent could ever want and almost never what it needs: a 1206×2622 picture costs about 4,000 tokens to view where the same screen at one pixel per point costs about 450. So the host decides the size. By default the image is scaled to **point scale**, one pixel per point of the tree root's frame, which is also the space of every frame in the tree and of `tapPoint`, so a frame read from the tree locates directly on the image; `Request.scale` keeps 2 or 3 pixels per point for hairlines and anti-aliasing. `Request.label` crops to one element's frame plus ``margin`` points, clipped to the screen.
///
/// **A picture that does not match the frames is not written.** Every crop and every coordinate the agent reads off the image assumes the image is the tree root's screen; an image whose aspect ratio differs from the root frame's by more than ``aspectTolerance`` would locate everything in the wrong place, so nothing is written and the line names both sizes.
///
/// **CoreGraphics in the core is the same deliberate exception `ScreenshotBrightness` makes:** this decodes and re-encodes a PNG, which is reachable by `swift test` here and would not be inside the runner.
public struct ScreenshotFit {
    /// The points added on every side of a cropped element's frame.
    public static let margin = 8.0

    /// How far the image's aspect ratio may differ from the root frame's, as a fraction of the frame's, before the image is taken for another screen.
    public static let aspectTolerance = 0.01

    /// Fits `png`, the runner's bytes, to `request` against `tree`, whose root frame is the screen in points, and writes the result to `url`; nothing is written on a refusal.
    ///
    /// Throws for the bytes not being an image this platform can decode, or for the file not being writable.
    public static func write(png: Data, tree: AXNode, request: Request, to url: URL) throws -> Outcome {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw Failure(description: "the screenshot is not an image this platform can decode")
        }
        let root = tree.frame
        guard root.width > 0, root.height > 0 else {
            return .refused("the screen read has no size to fit the screenshot to")
        }
        let imageAspect = Double(image.width) / Double(image.height)
        let rootAspect = root.width / root.height
        guard abs(imageAspect - rootAspect) / rootAspect <= aspectTolerance else {
            return .refused("the screenshot is \(image.width)×\(image.height) px and the screen read is \(size(root.width))×\(size(root.height)) pt: their shapes differ")
        }
        var region: AXNode.Frame?
        if let label = request.label {
            switch RouteTarget.choose(labelled: label, in: tree, reaching: .anything) {
            case let .chosen(candidate, among: tier):
                // `choose` takes the first of equals; a crop written around a guess is a wrong picture, so equals refuse.
                let equals = RouteTarget.distinctSpots(tier.filter { $0.rank == candidate.rank })
                guard equals.count == 1 else {
                    return .refused("\(equals.count) elements carry '\(label)' equally; name one by its identifier")
                }
                guard let clipped = cropRegion(around: candidate.node.frame, within: root) else {
                    return .refused("'\(label)' lies outside the screen read")
                }
                region = clipped
            case .none:
                return .refused("no element labelled '\(label)' on the screen read")
            case let .ambiguous(candidates):
                return .refused("'\(label)' matches \(candidates.count) elements on the screen read")
            }
        }
        let scale = Double(request.scale)
        guard let scaled = redrawn(image, width: Int((root.width * scale).rounded()), height: Int((root.height * scale).rounded())) else {
            throw Failure(description: "cannot scale the screenshot")
        }
        var result = scaled
        if let region {
            let left = (region.x * scale).rounded()
            let top = (region.y * scale).rounded()
            let right = ((region.x + region.width) * scale).rounded()
            let bottom = ((region.y + region.height) * scale).rounded()
            guard let cropped = scaled.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else {
                return .refused("'\(request.label ?? "")' lies outside the screen read")
            }
            result = cropped
        }
        try encode(result, to: url)
        return .written(path: url.path, width: result.width, height: result.height, scale: request.scale, label: request.label)
    }

    /// The answer's one line for `outcome`: the path and what it costs to view, or why there is no path.
    public static func line(_ outcome: Outcome) -> String {
        switch outcome {
        case let .written(path, width, height, scale, label):
            let tokens = grouped(ImageTokenEstimate.tokens(width: width, height: height))
            let scaleText = scale == 1 ? "point scale" : "\(scale)× point scale"
            let crop = label.map { ", '\($0)' + \(size(margin)) pt" } ?? ""
            return "screenshot: \(path) (\(width)×\(height) px, \(scaleText)\(crop), about \(tokens) tokens to view)"
        case let .refused(reason):
            return "screenshot: not written — \(reason)"
        }
    }
}

public extension ScreenshotFit {
    /// What the caller asked of the image.
    struct Request: Equatable, Sendable {
        /// Pixels per point of the tree root's frame, 1 (point scale), 2 or 3.
        public let scale: Int
        /// The label of the element to crop to, resolved in the tree as a `scrollTo` label is, or `nil` for the whole screen.
        public let label: String?

        /// `nil` for a scale outside 1…3, which the caller refuses in its own words rather than having this clamp it.
        public init?(scale: Int = 1, label: String? = nil) {
            guard (1 ... 3).contains(scale) else { return nil }
            self.scale = scale
            self.label = label
        }
    }

    /// What became of the request.
    enum Outcome: Equatable, Sendable {
        /// The image was written at `path`, `width` × `height` pixels at `scale` pixels per point, cropped to `label`'s element when it is not `nil`.
        case written(path: String, width: Int, height: Int, scale: Int, label: String?)
        /// Nothing was written, for this reason as the answer's line says it.
        case refused(String)
    }
}

private extension ScreenshotFit {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// `frame` outset by ``margin`` and clipped to the screen, relative to the screen's origin; `nil` when nothing of it is on the screen.
    static func cropRegion(around frame: AXNode.Frame, within root: AXNode.Frame) -> AXNode.Frame? {
        let left = max(frame.x - margin, root.x) - root.x
        let top = max(frame.y - margin, root.y) - root.y
        let right = min(frame.x + frame.width + margin, root.x + root.width) - root.x
        let bottom = min(frame.y + frame.height + margin, root.y + root.height) - root.y
        guard right > left, bottom > top else { return nil }
        return AXNode.Frame(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// `image` redrawn at `width` × `height` px **in its own colour space**, so each pixel keeps the colour the screenshot gave it.
    ///
    /// Drawn into another space, a Display P3 screenshot's saturated colours would be shifted or clipped, and a colour is what the screenshot is asked for. An image whose space is not RGB is drawn in sRGB.
    static func redrawn(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let own = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard width > 0, height > 0, let space = own ?? CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func encode(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure(description: "cannot create \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(description: "cannot write \(url.lastPathComponent)")
        }
    }

    /// A length in points without a trailing `.0`.
    static func size(_ points: Double) -> String {
        points.rounded() == points ? String(Int(points)) : String(format: "%.1f", points)
    }

    /// `4000` as `4,000`, whatever the machine's locale.
    static func grouped(_ count: Int) -> String {
        let digits = String(count)
        var result = ""
        for (offset, digit) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                result.append(",")
            }
            result.append(digit)
        }
        return String(result.reversed())
    }
}
