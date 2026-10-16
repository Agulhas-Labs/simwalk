//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a `tapPoint` step's touch lands on the screen, or why it is not made (SimWalk#29).
///
/// The runner's one decision about a point tap, kept here where a test can hold it: the runner reads the screen's frame and, for a point within an element, the frame of the element its label chose, and taps what this answers. **A refusal is the step not landing**, which the route loop reports as UNREACHABLE naming the step — never a touch somewhere near the point asked for.
///
/// Three refusals, each a touch that would otherwise land somewhere the step does not name:
/// - a point that is not two numbers, or a fraction of an element outside 0…1 — `validate` refuses both first, and this holds a walkbook that reached the runner some other way to the same rule;
/// - an element whose frame is empty: Health's chart leaves the previous period's bars in the tree at zero size, and every fraction of a zero-size frame is its one corner;
/// - a point beyond the screen — the half of an absolute point `validate` cannot check, not knowing the device, and a relative one whose element lies partly off screen.
public enum TapPointPlacement: Equatable, Sendable {
    /// Tap here, in screen points.
    case point(x: Double, y: Double)
    /// Tap nothing: `reason` says why, in the words an UNREACHABLE carries.
    case refused(reason: String)

    /// The point `at` names: within `element`'s frame when there is one, each coordinate a fraction of it; on the screen otherwise, in device points.
    ///
    /// The screen's edges count as on it, so `1,1` of an element flush with the screen's corner is tapped rather than refused over a boundary no touch can tell from the pixel inside it.
    public static func of(_ point: [Double], within element: AXNode.Frame?, onScreen screen: AXNode.Frame) -> Self {
        guard point.count == 2 else {
            return .refused(reason: "the point is \(point.count) number\(point.count == 1 ? "" : "s"), not an x and a y")
        }
        let written = Walkbook.RouteStep.rendered(point)
        var x = point[0]
        var y = point[1]
        if let element {
            guard point.allSatisfy({ (0 ... 1).contains($0) }) else {
                return .refused(reason: "\(written) is outside the element's frame — a point within an element is two fractions of it from 0 to 1")
            }
            guard element.width > 0, element.height > 0 else {
                return .refused(reason: "the element's frame is empty (\(Self.size(element)) at \(Self.origin(element))), so no point lies within it — the tree is holding an element that is not drawn")
            }
            x = element.x + x * element.width
            y = element.y + y * element.height
        }
        guard x >= screen.x, x <= screen.x + screen.width, y >= screen.y, y <= screen.maxY else {
            let what = element == nil ? written : "\(written) of the element's frame, \(Walkbook.RouteStep.rendered([x, y])),"
            return .refused(reason: "\(what) is outside the screen (\(Self.size(screen)) pt)")
        }
        return .point(x: x, y: y)
    }

    private static func size(_ frame: AXNode.Frame) -> String {
        "\(Walkbook.RouteStep.rendered([frame.width]))×\(Walkbook.RouteStep.rendered([frame.height]))"
    }

    private static func origin(_ frame: AXNode.Frame) -> String {
        Walkbook.RouteStep.rendered([frame.x, frame.y])
    }
}
