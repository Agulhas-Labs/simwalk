//
// Copyright © Agulhas Labs
//

import Foundation

/// One element of a captured accessibility tree: what it is, where it is, and what it says.
///
/// This is the machine-readable half of a capture (Brief §2.1) — "the accessibility tree, and every text run with its frame". The differ works from it rather than from pixels, which is where most of the ~10× saving comes from: section presence, order, layout boxes, truncation and overlap are all answerable here, and only the flagged ones need an image opened.
///
/// **It replaces a wrapped `debugDescription`.** The runner's first version wrote XCUITest's own debug string inside a JSON envelope, which meant every consumer — including this session, repeatedly — had to regex frames and labels back out of a format nobody promised to keep stable. A tree that has to be re-parsed to be used is not machine-readable; it is a screenshot of a tree.
public struct AXNode: Codable, Equatable, Sendable {
    /// The element's type, as XCUITest names it (`Button`, `StaticText`, `TabBar`).
    public var type: String
    /// Where it sits, in points, in the captured screen's coordinate space.
    public var frame: Frame
    /// Its accessibility label, when it has one.
    public var label: String?
    /// Its accessibility identifier, when the app sets one.
    public var identifier: String?
    /// Its value, for elements that carry one.
    public var value: String?
    /// Whether the element carries the selected trait — the one thing that separates the active segment of a picker from its four siblings.
    ///
    /// Recorded because a bundle that drops it cannot tell "selection is not exposed to VoiceOver" from "selection is exposed and the capture did not record it". A real audit filed the first against an app that was doing the second, and it cost a fix round to refute (SimWalk#2).
    public var isSelected: Bool
    /// Whether the element is enabled; `false` is a control the app is deliberately offering as unavailable.
    ///
    /// The counterpart of `isSelected`: a dimmed, unofferable control and a live one serialise identically without it, so "visibly disabled, never hidden" is a claim no bundle could check.
    public var isEnabled: Bool
    /// Children in tree order.
    public var children: [AXNode]

    public init(
        type: String,
        frame: Frame,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        children: [AXNode] = []
    ) {
        self.type = type
        self.frame = frame
        self.label = label
        self.identifier = identifier
        self.value = value
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.children = children
    }

    /// Omits `children` when there are none, and decodes a missing one as none.
    ///
    /// Leaves are most of a real screen's nodes — 94 of 154 on one measured detail screen — so `"children":[]` on each was pure weight in a file whose whole job is to be cheaper than the picture beside it. The optionals are already omitted by `JSONEncoder`; this is the one array that needed saying.
    ///
    /// **The two traits are written only when they are the unusual answer** — `isSelected` when true, `isEnabled` when false — for the same reason and with a second one behind it: almost every node on a screen is enabled and unselected, so writing both on all 154 of them would be most of the file, and a bundle written before they existed decodes to exactly the same tree it always did rather than to one asserting a selection it never observed.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(frame, forKey: .frame)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(value, forKey: .value)
        if isSelected {
            try container.encode(isSelected, forKey: .isSelected)
        }
        if !isEnabled {
            try container.encode(isEnabled, forKey: .isEnabled)
        }
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        frame = try container.decode(Frame.self, forKey: .frame)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        children = try container.decodeIfPresent([AXNode].self, forKey: .children) ?? []
    }
}

public extension AXNode {
    /// A layout box, stored as four numbers rather than a `CGRect` so the core stays free of CoreGraphics and the JSON shape is obvious to a reader.
    struct Frame: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// The bottom edge, which is what tells a reader whether an element was below the fold.
        public var maxY: Double {
            y + height
        }

        /// The left edge, which with the members below is what the geometry rules of `bundle audit` ask of where a frame sits.
        var minX: Double {
            x
        }

        var maxX: Double {
            x + width
        }

        var minY: Double {
            y
        }

        /// Whether the frame has any area — a zero-sized element is a container the app has not laid out, and is nowhere.
        var hasArea: Bool {
            width > 0 && height > 0
        }

        /// Whether any part of the frame falls inside `screen`.
        func isOnScreen(_ screen: AXNode.Frame) -> Bool {
            hasArea && maxX > screen.minX && minX < screen.maxX && maxY > screen.minY && minY < screen.maxY
        }

        /// How far the two frames overlap horizontally, in points; zero when they do not.
        func horizontalOverlap(with other: AXNode.Frame) -> Double {
            max(0, min(maxX, other.maxX) - max(minX, other.minX))
        }

        /// How far the two frames overlap vertically, in points; zero when they do not.
        func verticalOverlap(with other: AXNode.Frame) -> Double {
            max(0, min(maxY, other.maxY) - max(minY, other.minY))
        }

        /// Whether `other` lies inside this frame, each of its edges within `tolerance` points of being so.
        func contains(_ other: AXNode.Frame, tolerance: Double = 0) -> Bool {
            other.minX >= minX - tolerance && other.maxX <= maxX + tolerance && other.minY >= minY - tolerance && other.maxY <= maxY + tolerance
        }

        /// Whether the two frames share area of more than `tolerance` points in both directions.
        func intersects(_ other: AXNode.Frame, tolerance: Double = 0) -> Bool {
            horizontalOverlap(with: other) > tolerance && verticalOverlap(with: other) > tolerance
        }
    }

    /// Every node in tree order, this one first — the flattening most questions about a screen start from.
    var flattened: [AXNode] {
        [self] + children.flatMap(\.flattened)
    }

    /// Every node carrying text, with its frame: the "text runs" half of what a capture promises.
    var textRuns: [AXNode] {
        flattened.filter { node in
            guard let label = node.label else { return false }
            return !label.isEmpty
        }
    }

    /// The stable identifier this capture's screen is known by, or `nil` when nothing names it: one the app set on a container in the screen's content — or, when an alert, sheet, popover or page sheet covers the screen, on the topmost presentation's, and `nil` rather than the covered screen's when the presentation carries none.
    ///
    /// Only a container's own identifier: never a bar's, the keyboard's, an image's symbol name, a control's, a framework's, **a navigation bar's title** (localised, so it would change with the language a walk captures in) or **one shared by every element of a container** (SwiftUI's propagation, or a shared row identifier — it may name the rows).
    ///
    /// ``ScreenIdentifier`` states exactly what counts and what it does not recognise, carries where the value was read, and reports the two unstable identifiers when asked, for a caller that has to say so.
    var screenIdentifier: String? {
        ScreenIdentifier(of: self)?.value
    }
}

extension AXNode {
    /// The screen's extent in points: the root's frame, or — where the root reports none, as Apple's Settings' application node does — the first node beneath it that has an area (its window).
    var screenBounds: AXNode.Frame {
        flattened.first { $0.frame.hasArea }?.frame ?? frame
    }

    /// Declared rather than synthesised, because writing `encode(to:)` by hand to omit empty children turns the synthesis off.
    enum CodingKeys: String, CodingKey {
        case type
        case frame
        case label
        case identifier
        case value
        case isSelected
        case isEnabled
        case children
    }
}
