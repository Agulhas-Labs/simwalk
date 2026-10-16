//
// Copyright © Agulhas Labs
//

import Foundation

/// One thing a mirror step does to the phone before it reads: a tap, a swipe, a wheel scroll, or a View menu click (Brief §8).
///
/// **A value of the core's, so the answer can name it without the driver.** The driver turns each case into the guarded event or click; the label is what the answer's header says it did, in the spelling a caller typed it.
public enum MirrorAction: Equatable, Sendable {
    /// A tap at a fraction of the window.
    case tap(MirrorFraction)
    /// A drag between two fractions over `milliseconds`.
    case swipe(from: MirrorFraction, to: MirrorFraction, milliseconds: Double)
    /// `lines` lines of wheel at a fraction, `horizontal` or vertical.
    case scroll(lines: Int32, horizontal: Bool, position: MirrorFraction)
    /// A View menu item.
    case menu(MirrorMenuItem)

    /// The short text the answer's header and the capture's file name carry: `tap .50,.62`, `scroll 5 at .50,.50`, `menu Home Screen`.
    public var label: String {
        switch self {
        case let .tap(point):
            "tap \(Self.spell(point))"
        case let .swipe(start, end, milliseconds):
            "swipe \(Self.spell(start)) to \(Self.spell(end)) in \(Int(milliseconds)) ms"
        case let .scroll(lines, horizontal, point):
            "scroll\(horizontal ? " horizontal" : "") \(lines) at \(Self.spell(point))"
        case let .menu(item):
            "menu \(item.title)"
        }
    }

    private static func spell(_ fraction: MirrorFraction) -> String {
        MirrorFractionText.spell(x: fraction.x, y: fraction.y, decimals: 2)
    }
}
