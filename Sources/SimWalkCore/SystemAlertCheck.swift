//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a system alert covers the app, read from SpringBoard's own tree (SimWalk#28).
///
/// **The app's tree cannot say.** While SpringBoard draws an alert over the app — the notifications permission alert is the specimen — `app.snapshot()` goes on returning the app's own hierarchy, untouched, while the screenshot shows the alert. Filed together they are a capture of two different screens under one id, which every other check in the format passes. So a capture reads SpringBoard's tree beside the app's (`SettledCapture.take`), and an `Alert` there refuses it rather than filing either tree: SpringBoard's is not the screen the walkbook asked for, and the app's is not the screen that was photographed.
///
/// A sheet drawn *inside* the app's process needs nothing from here — HealthKit's authorization sheet is one, hosted in the app's own window where `app.snapshot()` already sees it.
public struct SystemAlertCheck {
    /// The alert covering the app in `springboard`, named by its title, or `nil` when none is there.
    public static func coveringAlert(in springboard: AXNode) -> String? {
        guard let alert = springboard.flattened.first(where: { $0.type == "Alert" }) else {
            return nil
        }
        let title = alert.label ?? alert.flattened.first { $0.type == "StaticText" && $0.label != nil }?.label
        return title.map { "a system alert '\($0)' covers the app" } ?? "an untitled system alert covers the app"
    }
}
