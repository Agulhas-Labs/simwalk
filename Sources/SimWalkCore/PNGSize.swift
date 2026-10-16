//
// Copyright © Agulhas Labs
//

import Foundation

/// The pixel dimensions a PNG declares in its header, read from the file's first bytes rather than by decoding it.
///
/// **No image framework, deliberately.** Pricing a screenshot needs two integers, and a PNG puts them 16 bytes in: the eight-byte signature, then the IHDR chunk's length and type, then width and height as big-endian 32-bit integers. Decoding the image to learn them would allocate the whole bitmap — tens of megabytes across a walk — to read 8 bytes, and would drag a platform framework into the one target that has to build for the simulator as well as the host.
///
/// It reads the header and nothing else: no CRC is checked and no other chunk is looked at, because nothing here is deciding whether the file is *valid* — only what a reader would have paid to look at it. A file that is not a PNG this understands answers `nil`, and the caller leaves it out of the weighing rather than guessing a size for it.
public struct PNGSize: Equatable, Sendable {
    /// The image's width in pixels.
    public let width: Int
    /// The image's height in pixels.
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The dimensions declared by the PNG at `url`, or `nil` when its first bytes are not a PNG header.
    public init?(contentsOf url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: Self.headerLength) else { return nil }
        self.init(header: header)
    }

    /// The dimensions declared in `header`, or `nil` when those bytes are not a PNG header.
    public init?(header: Data) {
        // Offsets matter here, so the bytes become an array first: slicing `Data` indexes by its own
        // (possibly non-zero) start index, which reads the wrong four bytes for anything that arrived
        // as a slice of a larger buffer.
        let bytes = [UInt8](header)
        guard bytes.count >= Self.headerLength,
              Array(bytes[0 ..< Self.signature.count]) == Self.signature,
              Array(bytes[12 ..< 16]) == Array(Self.chunkType.utf8)
        else {
            return nil
        }
        let width = Self.integer(bytes[16 ..< 20])
        let height = Self.integer(bytes[20 ..< 24])
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }

    /// How far into the file the two integers are: signature, chunk length, chunk type, width, height.
    static let headerLength = 24

    /// The eight bytes every PNG opens with.
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// The first chunk's type, which the format requires to be the image header.
    private static var chunkType: String {
        "IHDR"
    }

    /// Four bytes, most significant first — the byte order the format is written in.
    private static func integer(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}
