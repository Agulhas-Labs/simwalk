//
// Copyright © Agulhas Labs
//

import AppKit
import CoreGraphics
import Foundation
import SimWalkCore

/// Finds the iPhone Mirroring window through the window server, afresh on every call so a step survives the window being moved (Brief §8 "Coordinates are fractions").
///
/// **The largest phone-shaped layer-0 window the app owns on screen.** The app also owns layer-0 windows that are not the phone — strips the width of the display and 33 points tall, a 54-point square — and an onboarding window ("Welcome to iPhone Mirroring", 640×662 pt, larger than the phone's 383×843) that is on screen when no phone is connected. Phone-shaped means at least 1.5 times as tall as wide, which the onboarding window is not, so with only it on screen the lookup refuses rather than capturing it; only on-screen windows are considered, so a window on another Space or hidden is refused rather than captured blind.
public struct MirrorWindow {
    /// How many times taller than wide a window must be to be the phone.
    static let minimumAspect = 1.5

    /// The Mirroring window as the window server lists it now, refused when there is none.
    public static func current() throws(MirrorControlError) -> MirrorWindowFrame {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return try frame(among: windows)
    }

    /// Every on-screen window, front to back, and the displays: one snapshot for a gesture's hit test, taken just before it posts.
    ///
    /// Desktop elements are included, so a point off every app window is found landing on the desktop rather than in nothing.
    static func stack() -> MirrorWindowStack {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(UInt32(displays.count), &displays, &count)
        return MirrorWindowStack(windows: windows.compactMap(record), displays: displays.prefix(Int(count)).map { bounds(CGDisplayBounds($0)) })
    }

    /// One of the window server's dictionaries as a record, `nil` when it has no number or bounds; a missing alpha reads as opaque and a missing layer as 0, so an incomplete entry is counted as covering rather than passed over.
    static func record(_ window: [String: Any]) -> MirrorWindowStack.Window? {
        guard let number = window[kCGWindowNumber as String] as? NSNumber,
              let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary)
        else {
            return nil
        }
        return MirrorWindowStack.Window(
            windowID: number.uint32Value,
            owner: window[kCGWindowOwnerName as String] as? String ?? "",
            layer: (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            bounds: bounds(rect),
            bundleID: (window[kCGWindowOwnerPID as String] as? NSNumber).flatMap { NSRunningApplication(processIdentifier: pid_t($0.int32Value))?.bundleIdentifier }
        )
    }

    private static func bounds(_ rect: CGRect) -> MirrorWindowStack.Bounds {
        MirrorWindowStack.Bounds(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// The largest phone-shaped window owned by "iPhone Mirroring" at layer 0 in `windows` (the window server's own dictionaries, in its front-to-back order, so a tie goes to the front one).
    static func frame(among windows: [[String: Any]]) throws(MirrorControlError) -> MirrorWindowFrame {
        let candidates = windows.compactMap { window -> MirrorWindowFrame? in
            guard window[kCGWindowOwnerName as String] as? String == MirrorFocus.appName,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 0, rect.height >= Self.minimumAspect * rect.width
            else {
                return nil
            }
            return MirrorWindowFrame(windowID: number.uint32Value, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }
        guard let largest = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            throw .noWindow
        }
        return largest
    }
}
