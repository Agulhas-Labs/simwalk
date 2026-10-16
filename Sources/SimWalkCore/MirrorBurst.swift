//
// Copyright © Agulhas Labs
//

import Foundation

/// A tap followed by frames captured as fast as capture goes, each read afterwards: what a transition showed, frame by frame (Brief §8).
public struct MirrorBurst: Equatable, Sendable {
    /// The tap that started it.
    public let point: MirrorFraction
    /// The window as it was when the burst ran.
    public let window: MirrorWindowFrame
    /// How many frames were asked for.
    public let requested: Int
    /// The frames that were taken, in order, counted from 1.
    public let frames: [Frame]
    /// The refusal that ended the burst early, `nil` when every frame was taken.
    public let stoppedBy: MirrorFocusRefusal?
    /// The directory the frames' captures are in.
    public let directory: URL

    public init(point: MirrorFraction, window: MirrorWindowFrame, requested: Int, frames: [Frame], stoppedBy: MirrorFocusRefusal?, directory: URL) {
        self.point = point
        self.window = window
        self.requested = requested
        self.frames = frames
        self.stoppedBy = stoppedBy
        self.directory = directory
    }

    /// The label the answer's header carries: the tap that started it.
    public var label: String {
        MirrorAction.tap(point).label
    }
}

public extension MirrorBurst {
    /// One frame of a burst.
    struct Frame: Equatable, Sendable {
        /// Counted from 1, as the guard's `beforeFrame` is.
        public let index: Int
        /// Milliseconds from the tap to this frame's capture.
        public let millisecondsSinceTap: Int
        /// What Vision read in it.
        public let read: MirrorRead

        public init(index: Int, millisecondsSinceTap: Int, read: MirrorRead) {
            self.index = index
            self.millisecondsSinceTap = millisecondsSinceTap
            self.read = read
        }
    }
}
