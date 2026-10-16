//
// Copyright © Agulhas Labs
//

import Foundation

/// A place in the iPhone Mirroring window as fractions of its width and height, `0…1` on both axes (SimWalk#113, Brief §8 "A real device over iPhone Mirroring").
///
/// **A fraction, not a point, because the window moves.** A step written in screen points is wrong the moment someone drags the window, and one written in the phone's own points depends on a scale nothing on the Mac reports. A fraction survives both, and OCR boxes are served in the same fractions, so a line read off one answer can be tapped by the next without arithmetic on pixels.
///
/// **Refused outside `0…1`, and when not a number.** A value past an edge would post an event onto whatever lies beside the window — another app's content, the desktop — which is exactly the damage the focus guard exists to prevent.
public struct MirrorFraction: Equatable, Sendable {
    /// Across the window: 0 is its left edge, 1 its right.
    public let x: Double
    /// Down the window: 0 is its top edge, 1 its bottom (the top-left origin `CGEvent` uses).
    public let y: Double

    /// A fraction on each axis, refused naming the first axis that is not a finite value in `0…1`.
    public init(x: Double, y: Double) throws(OutOfRange) {
        try Self.check(x, axis: "x")
        try Self.check(y, axis: "y")
        self.x = x
        self.y = y
    }

    private static func check(_ value: Double, axis: String) throws(OutOfRange) {
        guard value.isFinite, (0 ... 1).contains(value) else {
            throw OutOfRange(axis: axis, value: value)
        }
    }
}

extension MirrorFraction.OutOfRange: CustomStringConvertible {
    /// The refusal's own sentence, for `TimedCall`, which prints `String(describing:)`.
    public var description: String {
        errorDescription ?? "not a fraction of the window"
    }
}

extension MirrorFraction.OutOfRange: UsageFailureClassifiable {
    /// A coordinate the caller gave outside the window: a bad argument.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}

public extension MirrorFraction {
    /// A coordinate outside the window: a bad argument, refused before anything is posted (exit 1, not the focus refusal's 3 — retrying it changes nothing).
    struct OutOfRange: LocalizedError, Equatable, Sendable {
        /// `x` or `y`.
        public let axis: String
        /// The value given, `nan` and `inf` included.
        public let value: Double

        public var errorDescription: String? {
            "\(axis) = \(value) is not a fraction of the iPhone Mirroring window — mirror coordinates run 0…1 on both axes"
        }

        /// `Double` is `Equatable` by IEEE rules, under which `nan` equals nothing; a refusal of `nan` still equals another refusal of `nan`.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.axis == rhs.axis && (lhs.value == rhs.value || (lhs.value.isNaN && rhs.value.isNaN))
        }
    }
}
