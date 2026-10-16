//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A capture under a SpringBoard alert is refused, because the app's tree beside it describes a screen the picture does not show (SimWalk#28).
struct SystemAlertCheckTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// SpringBoard's tree with the app in front and nothing over it: windows and plain containers only.
    @Test
    func springboardWithNoAlertCoversNothing() {
        let springboard = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Window", frame: Self.screen, children: [AXNode(type: "Other", frame: Self.screen)]),
        ])

        #expect(SystemAlertCheck.coveringAlert(in: springboard) == nil)
    }

    /// The notifications permission alert as SpringBoard draws it: the refusal names it by its title, so a reader knows what was in the way.
    @Test
    func analertInSpringboardRefusesTheCaptureNamingIt() {
        let title = "“PermissionFixture” Would Like to Send You Notifications"
        let springboard = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Window", frame: Self.screen, children: [
                AXNode(type: "Alert", frame: Self.screen, label: title, children: [
                    AXNode(type: "Button", frame: Self.screen, label: "Allow"),
                ]),
            ]),
        ])

        #expect(SystemAlertCheck.coveringAlert(in: springboard) == "a system alert '\(title)' covers the app")
    }

    /// An alert with no label of its own is named by its first text, and one with no text at all still refuses.
    @Test
    func anunlabelledAlertIsNamedByItsTextOrRefusedUntitled() {
        let titled = AXNode(type: "Alert", frame: Self.screen, children: [AXNode(type: "StaticText", frame: Self.screen, label: "Allow?")])
        let bare = AXNode(type: "Alert", frame: Self.screen)

        #expect(SystemAlertCheck.coveringAlert(in: AXNode(type: "Application", frame: Self.screen, children: [titled])) == "a system alert 'Allow?' covers the app")
        #expect(SystemAlertCheck.coveringAlert(in: AXNode(type: "Application", frame: Self.screen, children: [bare])) == "an untitled system alert covers the app")
    }
}
