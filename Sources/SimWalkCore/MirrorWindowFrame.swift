//
// Copyright © Agulhas Labs
//

import Foundation

/// The iPhone Mirroring window as the window server placed it at one moment: its id and its frame in global display points, top-left origin, as `CGEvent` positions are.
///
/// Read afresh on every call (the driver's `MirrorWindow.current()`), never remembered, so a step survives the window being moved between calls. A value of the core's own rather than a `CGRect` because the core builds for iOS without CoreGraphics' event and window APIs, and the mapping from a fraction to a point is a decision ``point(for:)`` makes where `swift test` sees it.
public struct MirrorWindowFrame: Equatable, Sendable {
    /// The window server's id for the window — what `screencapture -l` captures, so an overlapping window is never in the picture.
    public let windowID: UInt32
    /// The window's left edge, in global display points.
    public let x: Double
    /// The window's top edge, in global display points (top-left origin).
    public let y: Double
    /// The window's width in points.
    public let width: Double
    /// The window's height in points.
    public let height: Double

    public init(windowID: UInt32, x: Double, y: Double, width: Double, height: Double) {
        self.windowID = windowID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The display point `fraction` names in this window: its origin plus the fraction of its size on each axis, inside the half-open rectangle the window covers.
    ///
    /// `x + width` is the first point past the right edge, which belongs to whatever lies beside the window, so a fraction's offset stops one point short of the far edge on each axis: `1` lands on the window's last point, never beside it.
    public func point(for fraction: MirrorFraction) -> Point {
        Point(x: x + min(width * fraction.x, width - 1), y: y + min(height * fraction.y, height - 1))
    }

    /// The point `fraction` names, refused when it lies outside the phone's screen inside the window: in the transparent border round it or a rounded corner, where a click passes through to the window behind.
    ///
    /// **The shape is measured, not assumed.** The window's alpha, captured by window id on 14 Oct (383×843 pt at 2×), is transparent 8 pt in from the left, right and bottom and 38 pt from the top, and the screen inside it has rounded corners a 57.25 pt circle cuts conservatively (it refuses every transparent pixel, and a few opaque ones on the curve, which is a continuous corner rather than a circle). The constants are fractions of the window's width, so a window shown larger or smaller keeps its shape.
    public func target(for fraction: MirrorFraction) throws(PassThrough) -> Point {
        let point = point(for: fraction)
        let left = Self.sideInsetFraction * width
        let right = width - Self.sideInsetFraction * width
        let top = Self.topInsetFraction * width
        let bottom = height - Self.bottomInsetFraction * width
        let radius = Self.cornerRadiusFraction * width
        let localX = point.x - x
        let localY = point.y - y
        guard localX >= left, localX < right, localY >= top, localY < bottom else {
            throw PassThrough(fraction: fraction)
        }
        let beyondX = max(left + radius - localX, localX - (right - radius), 0)
        let beyondY = max(top + radius - localY, localY - (bottom - radius), 0)
        guard beyondX * beyondX + beyondY * beyondY <= radius * radius else {
            throw PassThrough(fraction: fraction)
        }
        return point
    }
}

public extension MirrorWindowFrame {
    /// The transparent border left and right of the phone's screen: 8 pt of the 383 pt window.
    static let sideInsetFraction = 8.0 / 383
    /// The transparent border above the phone's screen, where Mirroring's own title bar shows on hover: 38 pt of the 383 pt width.
    static let topInsetFraction = 38.0 / 383
    /// The transparent border below the phone's screen: 8 pt of the 383 pt width.
    static let bottomInsetFraction = 8.0 / 383
    /// The radius of the circle that cuts the screen's rounded corners: 58 pt of the 383 pt width, the measured 57.25 pt rounded up so the cut stays on the refusing side.
    static let cornerRadiusFraction = 58.0 / 383

    /// A fraction that names a point of the window the phone's screen does not cover: a bad argument (exit 1), because the click would pass through to the window behind and a retry changes nothing.
    struct PassThrough: LocalizedError, Equatable, Sendable {
        /// The fraction given.
        public let fraction: MirrorFraction

        public init(fraction: MirrorFraction) {
            self.fraction = fraction
        }

        public var errorDescription: String? {
            "x = \(fraction.x), y = \(fraction.y) lies in the iPhone Mirroring window's transparent border or a rounded corner of the phone's screen, where a click passes through to the window behind — move it onto the screen"
        }
    }
}

extension MirrorWindowFrame.PassThrough: UsageFailureClassifiable {
    /// A fraction the caller gave that lies off the phone's screen: a bad argument, not a failure of the tool.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}

public extension MirrorWindowFrame {
    /// A point in global display coordinates, top-left origin: where a mouse or wheel event is posted.
    struct Point: Equatable, Sendable {
        /// Points from the left of the main display.
        public let x: Double
        /// Points from the top of the main display.
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }
}
