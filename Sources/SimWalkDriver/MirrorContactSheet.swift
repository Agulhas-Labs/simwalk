//
// Copyright © Agulhas Labs
//

import AppKit
import Foundation
import SimWalkCore

/// One image of a burst's frames side by side, each labelled with its number and how long after the tap it was taken (`f03 +412ms`), so an animation can be judged at a glance instead of by opening sixty files.
///
/// **Drawn into a bitmap of known pixel size** rather than an `NSImage` focus, whose size follows the display's scale: the sheet is the same size on every Mac, which is what lets a test state it. Tiles are `tileWidth` wide and as tall as the first frame's aspect makes them; a frame that cannot be read leaves its tile blank rather than failing the sheet, since the rest still show what happened.
public struct MirrorContactSheet {
    /// Tiles per row.
    static let columns = 6
    /// Each tile's width in pixels.
    static let tileWidth = 200

    /// Writes `sheet.png` into the burst's directory and returns its URL, or `nil` for a burst that took no frames.
    public static func write(_ burst: MirrorBurst) throws -> URL? {
        let tiles = burst.frames.map { frame in
            Tile(file: frame.read.path, label: String(format: "f%02d +%dms", frame.index, frame.millisecondsSinceTap))
        }
        guard !tiles.isEmpty else { return nil }
        let url = burst.directory.appendingPathComponent("sheet.png")
        try render(tiles, to: url)
        return url
    }

    /// Tiles `tiles` six to a row and writes the PNG to `url`.
    static func render(_ tiles: [Tile], to url: URL) throws {
        guard let first = tiles.compactMap({ NSImage(contentsOf: $0.file) }).first, first.size.width > 0 else {
            throw MirrorControlError.captureMissing(path: tiles.first?.file.path ?? url.path)
        }
        let width = tileWidth
        let height = max(1, Int((Double(width) * first.size.height / first.size.width).rounded()))
        let columns = min(Self.columns, tiles.count)
        let rows = (tiles.count + Self.columns - 1) / Self.columns
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width * columns, pixelsHigh: height * rows, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw MirrorControlError.captureFailed(reason: "the contact sheet's bitmap could not be made")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width * columns, height: height * rows).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.red, .backgroundColor: NSColor.white,
        ]
        for (offset, tile) in tiles.enumerated() {
            let rect = NSRect(x: (offset % Self.columns) * width, y: (rows - offset / Self.columns - 1) * height, width: width, height: height)
            NSImage(contentsOf: tile.file)?.draw(in: rect)
            (tile.label as NSString).draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 4), withAttributes: attributes)
        }
        context.flushGraphics()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw MirrorControlError.captureFailed(reason: "the contact sheet could not be encoded as a PNG")
        }
        try data.write(to: url)
    }
}

extension MirrorContactSheet {
    /// One frame's image and its label.
    struct Tile: Equatable {
        let file: URL
        let label: String
    }
}
