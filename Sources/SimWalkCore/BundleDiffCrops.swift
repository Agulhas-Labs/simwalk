//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO

/// What writing a diff's crops came to: for each flag's crop, the file it went to, or why there is none.
///
/// **CoreGraphics and ImageIO here follow `ScreenshotBrightness`**, the core's one other image reader: both ship on every platform the package builds for, and keeping the crop in the core makes it reachable by `swift test` and shared by both faces through one `answer()`.
public struct BundleDiffCrops: Equatable, Sendable {
    public var outcomes: [Key: Outcome]
    /// The directory the crops were written into; the flag lines name their files bare and the header names this once.
    public var directory: String

    public init(outcomes: [Key: Outcome] = [:], directory: String = "") {
        self.outcomes = outcomes
        self.directory = directory
    }

    /// How many crops should have been written and were not.
    public var failedCount: Int {
        outcomes.values.filter {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }.count
    }
}

public extension BundleDiffCrops {
    /// Which crop of which flag: the state, the flag's 1-based position among the state's flags, the crop's 1-based position among the flag's, and the side the crop shows.
    ///
    /// **The position is part of the key** because a flag can carry two crops on one side (overlapping sections), and side alone would let the second overwrite the first.
    struct Key: Hashable, Sendable {
        public var screen: String
        public var state: String
        public var flag: Int
        public var crop: Int
        public var side: BundleDiff.Side

        public init(screen: String, state: String, flag: Int, crop: Int, side: BundleDiff.Side) {
            self.screen = screen
            self.state = state
            self.flag = flag
            self.crop = crop
            self.side = side
        }
    }

    /// What became of one crop.
    enum Outcome: Equatable, Sendable {
        /// Written to this path.
        case written(String)
        /// Nothing of the section is in the screenshot, so there is nothing to crop.
        case notInScreenshot
        /// The crop should exist and could not be made; the reason.
        case failed(String)
    }

    /// Refuses a directory that already holds something, or a path that is not a directory, without creating anything.
    static func requireFresh(_ directory: URL, fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else {
            throw BundleDiffError.cropsNotWritable(path: directory.path, reason: "it is a file")
        }
        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw BundleDiffError.cropsNotWritable(path: directory.path, reason: error.localizedDescription)
        }
        guard entries.isEmpty else { throw BundleDiffError.cropsDirectoryNotEmpty(path: directory.path, entries: entries.count) }
    }

    /// Writes one PNG per crop of `diff` that is in its screenshot, into `directory`, named `<screen>__<state>__<n>.png`.
    ///
    /// **`n` counts the state's crops in flag order, from 1, whether or not each has a file** — so a crop's name does not move when another in the same state is not in the screenshot, and one flag with a crop on each side takes two consecutive numbers.
    ///
    /// **The separator is `__`, which an id or a slug does not contain**, so two pairs of ids cannot name one file; a target that exists all the same is left as it is and its crop is reported as not written.
    ///
    /// The pixel rect is the point rect times the screenshot's scale (its PNG width over the tree's root width, the viewport), floored at the origin and ceiled at the far edge so the section is never trimmed, then clipped to the image.
    static func write(_ diff: BundleDiff, reference: CaptureBundle, run: CaptureBundle, into directory: URL, fileManager: FileManager = .default) throws -> BundleDiffCrops {
        try requireFresh(directory, fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw BundleDiffError.cropsNotWritable(path: directory.path, reason: error.localizedDescription)
        }
        var source = ScreenshotSource(reference: reference, run: run)
        var outcomes: [Key: Outcome] = [:]
        for screen in diff.screens {
            for state in screen.states {
                var number = 0
                for (index, flag) in state.flags.enumerated() {
                    for (cropIndex, crop) in flag.crops.enumerated() {
                        number += 1
                        let key = Key(screen: screen.id, state: state.slug, flag: index + 1, crop: cropIndex + 1, side: crop.side)
                        guard crop.visibility != .notInScreenshot else {
                            outcomes[key] = .notInScreenshot
                            continue
                        }
                        let name = "\(fileStem(screen.id))__\(fileStem(state.slug))__\(number).png"
                        let target = directory.appendingPathComponent(name)
                        guard !fileManager.fileExists(atPath: target.path) else {
                            outcomes[key] = .failed("\(name) already exists")
                            continue
                        }
                        do {
                            let image = try source.image(for: crop, screen: screen.id)
                            try write(image.cropped(to: crop.rect), to: target)
                            outcomes[key] = .written(target.path)
                        } catch {
                            outcomes[key] = .failed(String(describing: error))
                        }
                    }
                }
            }
        }
        return BundleDiffCrops(outcomes: outcomes, directory: directory.path)
    }
}

private extension BundleDiffCrops {
    /// A screen id or slug as one path component.
    static func fileStem(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: "_")
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    struct Screenshot {
        let image: CGImage
        /// Pixels per point: the PNG's width over the tree's root width.
        let scale: Double

        func cropped(to rect: AXNode.Frame) throws -> CGImage {
            let left = max(0, (rect.x * scale).rounded(.down))
            let top = max(0, (rect.y * scale).rounded(.down))
            let right = min(Double(image.width), ((rect.x + rect.width) * scale).rounded(.up))
            let bottom = min(Double(image.height), ((rect.y + rect.height) * scale).rounded(.up))
            guard right > left, bottom > top, let cropped = image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else {
                throw Failure(description: "the section's rect lies outside the \(image.width)x\(image.height) screenshot")
            }
            return cropped
        }
    }

    /// Each side's screenshots, decoded once however many flags crop them.
    struct ScreenshotSource {
        let reference: CaptureBundle
        let run: CaptureBundle
        private var cache: [String: Screenshot] = [:]

        init(reference: CaptureBundle, run: CaptureBundle) {
            self.reference = reference
            self.run = run
        }

        mutating func image(for crop: SectionCrop, screen: String) throws -> Screenshot {
            let key = "\(crop.side.rawValue)/\(crop.screenshotPath)"
            if let cached = cache[key] {
                return cached
            }
            let bundle = crop.side == .reference ? reference : run
            guard let capture = bundle.manifest.screens.first(where: { $0.id == screen })?.captures.first(where: { $0.screenshotPath == crop.screenshotPath }) else {
                throw Failure(description: "the \(crop.side.rawValue) bundle records no capture at \(crop.screenshotPath)")
            }
            let url = bundle.screenshotURL(for: capture)
            let viewport = try bundle.axTree(for: capture).frame.width
            guard viewport > 0, let size = PNGSize(contentsOf: url) else {
                throw Failure(description: "cannot size \(crop.screenshotPath) against its tree")
            }
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw Failure(description: "cannot decode \(crop.screenshotPath)")
            }
            let screenshot = Screenshot(image: image, scale: Double(size.width) / viewport)
            cache[key] = screenshot
            return screenshot
        }
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure(description: "cannot create \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(description: "cannot write \(url.lastPathComponent)")
        }
    }
}
