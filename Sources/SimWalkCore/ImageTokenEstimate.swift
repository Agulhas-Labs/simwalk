//
// Copyright © Agulhas Labs
//

import Foundation

/// What a screenshot costs a model that looks at it, estimated from its pixels alone.
///
/// A walk's output is mostly pictures, so a saving stated only in bytes of tree would leave out the expensive half. An image is not priced by its file size — a 300 kB PNG and a 30 kB PNG of the same screen cost the same to look at — so it is priced by the pixels that survive the resize every image goes through on the way in.
///
/// **Two constants, both stated wherever a figure derived from them is printed.** An image whose long edge exceeds ``longEdgeCap`` (2576 px) is scaled down to fit it, both edges by the same factor; the resulting area is then charged at one token per ``pixelsPerToken`` (750) pixels, rounded up, because a fraction of a tile is still a tile. The scale factor is applied to the area without rounding the intermediate edges — rounding them first moves the answer by a token either way, which is a different arithmetic pretending to be the same one.
///
/// **Conservative, like every estimate here.** The cap only ever *reduces* the count, so an image read at its full size costs at least what this says; and the tile ratio is the coarse end of what these images tokenize at. The figure is a floor, and the faces that print it print the cap beside it so the arithmetic can be checked.
public struct ImageTokenEstimate {
    /// The longest edge an image is scaled to fit before it is read; a smaller image is read as it is.
    public static let longEdgeCap = 2576

    /// Pixels per token, once the image is inside the cap.
    public static let pixelsPerToken = 750

    /// The tokens an image of `width` × `height` pixels amounts to, or zero for a size that is not an image.
    public static func tokens(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let longEdge = Double(max(width, height))
        let scale = longEdge > Double(longEdgeCap) ? Double(longEdgeCap) / longEdge : 1
        let pixels = Double(width) * scale * Double(height) * scale
        return Int((pixels / Double(pixelsPerToken)).rounded(.up))
    }

    /// The tokens an image of `size` amounts to.
    public static func tokens(of size: PNGSize) -> Int {
        tokens(width: size.width, height: size.height)
    }
}
