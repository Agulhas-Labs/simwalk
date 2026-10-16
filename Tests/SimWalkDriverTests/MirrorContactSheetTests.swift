//
// Copyright © Agulhas Labs
//

import AppKit
import Foundation
@testable import SimWalkDriver
import Testing

/// The contact sheet's geometry over small generated frames: six to a row, 200 px tiles, one PNG.
struct MirrorContactSheetTests {
    @Test
    func threeFramesTileIntoOneRowTwoHundredPixelsEach() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sheet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tiles = try (1 ... 3).map { index in
            try MirrorContactSheet.Tile(file: Self.png(in: directory, named: "f\(index).png", width: 100, height: 200), label: "f0\(index) +\(index * 100)ms")
        }
        let sheet = directory.appendingPathComponent("sheet.png")

        try MirrorContactSheet.render(tiles, to: sheet)

        let image = try #require(try NSBitmapImageRep(data: Data(contentsOf: sheet)))

        #expect(image.pixelsWide == 600)
        #expect(image.pixelsHigh == 400)
    }

    @Test
    func sevenFramesWrapToASecondRow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sheet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try Self.png(in: directory, named: "f.png", width: 100, height: 100)
        let sheet = directory.appendingPathComponent("sheet.png")

        try MirrorContactSheet.render(Array(repeating: MirrorContactSheet.Tile(file: file, label: "f"), count: 7), to: sheet)

        let image = try #require(try NSBitmapImageRep(data: Data(contentsOf: sheet)))

        #expect(image.pixelsWide == 1200)
        #expect(image.pixelsHigh == 400)
    }

    private static func png(in directory: URL, named name: String, width: Int, height: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), sourceLocation: sourceLocation)
        let url = directory.appendingPathComponent(name)
        try #require(bitmap.representation(using: .png, properties: [:]), sourceLocation: sourceLocation).write(to: url)
        return url
    }
}
