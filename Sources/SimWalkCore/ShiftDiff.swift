//
// Copyright © Agulhas Labs
//

import Foundation

/// The comparison of two captures' layout shifts (SimWalk#67, M3): presence only, by element identity.
///
/// **Form, never value.** The settle time, the landing time and the read count and spacing are never compared, and a shift's box, path and time never decide a match: only `(type, identifier, label)` does, so a keyboard shift on every walk is on both sides and flags nothing.
struct ShiftDiff: Equatable {
    var flags: [ScreenDiff.ShiftFlag] = []
    var notes: [ScreenDiff.ShiftNote] = []
    /// Whether both sides carried a shift record, so that no flag means no difference.
    var compared = false

    /// The shifts one side has more of than the other, as flags; a note where only one side recorded shifts, and nothing where neither did.
    static func compare(slug: String, reference: CaptureManifest.Motion?, run: CaptureManifest.Motion?) -> ShiftDiff {
        switch (reference?.shifts, run?.shifts) {
        case let (referenceShifts?, runShifts?):
            ShiftDiff(
                flags: excess(of: referenceShifts, over: runShifts, side: .reference, slug: slug) + excess(of: runShifts, over: referenceShifts, side: .run, slug: slug),
                compared: true
            )
        case (nil, nil):
            ShiftDiff()
        case (nil, _?):
            ShiftDiff(notes: [ScreenDiff.ShiftNote(slug: slug, missingSide: .reference)])
        case (_?, nil):
            ShiftDiff(notes: [ScreenDiff.ShiftNote(slug: slug, missingSide: .run)])
        }
    }

    /// The shifts of `side` whose identity occurs more often there than on the other side, the later occurrences being the ones left over.
    private static func excess(of shifts: [CaptureManifest.Motion.Shift], over others: [CaptureManifest.Motion.Shift], side: BundleDiff.Side, slug: String) -> [ScreenDiff.ShiftFlag] {
        var remaining: [Identity: Int] = [:]
        for other in others {
            remaining[Identity(other.element), default: 0] += 1
        }
        return shifts.compactMap { shift in
            let identity = Identity(shift.element)
            if let left = remaining[identity], left > 0 {
                remaining[identity] = left - 1
                return nil
            }
            return ScreenDiff.ShiftFlag(slug: slug, side: side, shift: shift)
        }
    }
}

private extension ShiftDiff {
    /// What pairs a shift across two runs: the element's own name, never `within`.
    ///
    /// `within` is an ancestor's label, a value that can change between runs ("Inbox, 3 unread"), and a baseline recorded before it existed has none, so keying on it would flag an unchanged shift on either.
    struct Identity: Hashable {
        let type: String
        let identifier: String?
        let label: String?

        init(_ element: CaptureManifest.Motion.Element) {
            type = element.type
            identifier = element.identifier
            label = element.label
        }
    }
}
