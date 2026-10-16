//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a mirror call could not go ahead, other than focus: each a refusal (exit 1) naming its cause (Brief §8).
///
/// Lost focus is ``MirrorFocusRefusal``, kept apart because its answer is a retry.
public enum MirrorControlError: LocalizedError, Equatable, Sendable {
    /// No iPhone Mirroring window is on screen.
    case noWindow
    /// `screencapture` exited non-zero, with the line it left.
    case captureFailed(reason: String)
    /// `screencapture` exited zero but left no image, or an empty one, at `path`.
    case captureMissing(path: String)
    /// The View menu click failed, with the line `osascript` left.
    case noMenuItem(title: String, reason: String)

    /// System Events could not be asked which app is frontmost, with the error AppleScript gave.
    case systemEventsUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noWindow:
            "no \(MirrorFocus.appName) window on screen — the app is not running, the phone is not connected, or its window is on another Space"
        case let .captureFailed(reason):
            "could not capture the \(MirrorFocus.appName) window: \(reason)"
        case let .captureMissing(path):
            "screencapture wrote no image at \(path) — Screen Recording is likely not granted to the app running simwalk (System Settings → Privacy & Security → Screen Recording)"
        case let .systemEventsUnavailable(reason):
            "could not ask System Events which app is frontmost (\(reason)) — allow the app running simwalk under System Settings → Privacy & Security → Automation (System Events)"
        case let .noMenuItem(title, reason):
            "no View menu item '\(title)' in \(MirrorFocus.appName): \(reason)"
        }
    }
}

extension MirrorControlError: CustomStringConvertible {
    /// The refusal's own sentence, for `TimedCall`, which prints `String(describing:)`.
    public var description: String {
        errorDescription ?? "a mirror call could not go ahead"
    }
}

extension MirrorControlError: UsageFailureClassifiable {
    /// A missing window, capture permission or Automation grant is the Mac's setup, not a fault in the tool; a capture that failed or a menu item that was not there is the tool meeting something it did not expect.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .noWindow, .captureMissing, .systemEventsUnavailable: .setupFailed
        case .captureFailed, .noMenuItem: .toolError
        }
    }
}
