//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO

/// A screenshot reduced to a small grid of brightness cells, so a screen whose accessibility tree carries no text can still be told apart from another (SimWalk#150).
///
/// **Why it exists.** An app that draws into one Metal view exposes a tree with nothing a reader lists, so `screen <hash>` and the step's delta stay the same however much the tap changed. The picture is the only witness left, and this is the cheapest form of it that a hash and a comparison can both use.
///
/// **Sixteen columns.** Wide enough that a button-sized change moves several cells, narrow enough that the signature is a few hundred bytes and each cell averages hundreds of pixels, which smooths away anti-aliasing and a ticking clock. The rows follow the image's aspect, so a portrait phone's app is 16 by about 35 and a landscape phone's 16 by 7. The image is the screen's, turned upright when the device is landscape (SimWalk#221), wherever the signature is taken (SimWalk#150). Each cell is the area's mean luma, taken by drawing the image into a grayscale context at high interpolation, the same averaging ``ScreenshotBrightness`` relies on.
///
/// **Two resolutions, on purpose.** The hash must hold still on a screen nobody touched, ``ScreenHash``'s own rule, so ``hashToken`` keeps only four levels per cell. Identical pixels give an identical hash; a small change moves it only when a cell's mean crosses a level boundary (a cell at 63 becomes 64 on one level of change), so a still screen is stable and a slightly moving one may not be. ``changedFraction(to:)`` reports how much moved, so it counts a cell once it differs by more than ``cellTolerance``, sixteen levels.
///
/// **CoreGraphics in the core** is the deliberate exception ``ScreenshotBrightness`` explains.
public struct PixelSignature: Codable, Equatable, Sendable {
    /// The grid's width, in cells.
    public static let gridColumns = 16
    /// How far a cell's luma may differ, out of 255, before ``changedFraction(to:)`` counts it as changed.
    public static let cellTolerance = 16
    /// The fraction of the screen a guard on a text-less screen lets move (SimWalk#226): a different screen changes most cells; an idle animation a few.
    public static let guardTolerance = 0.1

    /// The grid's width, in cells.
    public let columns: Int
    /// The grid's height, in cells.
    public let rows: Int
    /// The mean luma of each cell, row by row from the top.
    public let cells: [UInt8]

    /// A signature of the given grid, which tests build to move an exact number of cells.
    init(columns: Int, rows: Int, cells: [UInt8]) {
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    /// The signature of a PNG, or `nil` when the bytes are not an image this platform can decode or the image has no area.
    public init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0
        else {
            return nil
        }
        let columns = Self.gridColumns
        let rows = max(1, Int((Double(columns * image.height) / Double(image.width)).rounded()))
        var cells = [UInt8](repeating: 0, count: columns * rows)
        let drawn = cells.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return nil }
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    /// The fraction of cells, 0…1, whose luma differs from `other`'s by more than ``cellTolerance``; a different grid shape (the screen turned) is `1`.
    public func changedFraction(to other: PixelSignature) -> Double {
        guard columns == other.columns, rows == other.rows, cells.count == other.cells.count, !cells.isEmpty else { return 1 }
        let changed = zip(cells, other.cells).filter { abs(Int($0) - Int($1)) > Self.cellTolerance }.count
        return Double(changed) / Double(cells.count)
    }

    /// The signature as text for ``ScreenHash``: the grid shape, then each cell at four levels as a digit.
    var hashToken: String {
        "\(columns)x\(rows):" + cells.map { String($0 >> 6) }.joined()
    }

    /// Whether `tree` has no text a reader lists, so the screen hash and the delta have nothing to go on but the picture.
    public static func isNeeded(for tree: AXNode) -> Bool {
        BundleScreenQuery.lines(of: tree).isEmpty
    }
}
