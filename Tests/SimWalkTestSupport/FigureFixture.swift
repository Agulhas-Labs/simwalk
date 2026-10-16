//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Screens drawing one figure, and bundles holding them, for the value oracle's tests.
public struct FigureFixture {
    /// A screen whose figure text is `text`, carrying `identifier` when given, beside a `Steps` heading.
    public static func screen(text: String, identifier: String? = "steps-today") -> AXNode {
        AXNode(type: "Application", frame: ScreenTreeFixture.screenFrame, label: "RouteFixture", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 120, width: 120, height: 22), label: "Steps"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 150, width: 160, height: 40), label: text, identifier: identifier),
        ])
    }

    /// A real app's Today screen: `2,703` on screen, in `en_US`.
    public static func figureBundle(in directory: TemporaryDirectory, text: String = "2,703", locale: String = "en_US", unreachable: [String] = [], walkbookHash: String? = nil) throws -> CaptureBundle {
        let captures = [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light, locale: locale), tree: screen(text: text))]
        guard let walkbookHash else {
            return try CaptureBundleFixture.write(in: directory, captures: captures, unreachable: unreachable)
        }
        return try CaptureBundleFixture.write(in: directory, captures: captures, unreachable: unreachable, walkbookHash: walkbookHash)
    }

    /// A walkbook asking for `steps-today` on `today` under both of that app's windows.
    public static func figureWalkbook(element: String = "steps-today") -> Walkbook {
        Walkbook(
            name: "example",
            appBundleID: "dev.simwalk.route-fixture",
            screens: [
                Walkbook.Screen(
                    id: "today",
                    route: [.tab(label: "Today")],
                    states: [Walkbook.CaptureState(theme: .light, locale: "en_US")],
                    figures: [Walkbook.Figure(id: "steps-today", element: element, windows: ["midnight", "rolling24h"])]
                ),
            ],
            oracle: Walkbook.Oracle(command: ["/bin/sh", "fixed-oracle.sh", "fixed"])
        )
    }
}
