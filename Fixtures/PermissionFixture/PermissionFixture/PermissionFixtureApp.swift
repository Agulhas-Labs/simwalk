//
// Copyright © Agulhas Labs
//

import HealthKit
import SwiftUI
import UserNotifications

/// Asks for HealthKit authorization, then for notifications, and says so once both have been answered (SimWalk#28).
///
/// The two requests run one after the other rather than together, so a walk meets them in a fixed order: the HealthKit sheet first, then the notifications alert.
///
/// Launched with `-ownAllowPage`, it asks for nothing until told to: its first screen pushes a page of the app's own holding a button labelled `Allow`, the control a `systemTap 'Allow'` must never take (SimWalk#39, scenario A), and either screen's `Ask for permissions` raises the same two sheets.
@main
struct PermissionFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-ownAllowPage") {
                OwnAllowRoot()
            } else {
                AskOnLaunch()
            }
        }
    }
}

/// The fixture as SimWalk#28 built it: both requests made as the screen appears.
private struct AskOnLaunch: View {
    @State private var answered = false

    var body: some View {
        Group {
            if answered {
                Text("Both permissions answered")
                    .accessibilityIdentifier("permissions-answered-label")
            } else {
                Text("Asking for permissions")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(answered ? "permissions-answered" : "permissions-asking")
        .task {
            await askForBoth()
            answered = true
        }
    }
}

/// A navigation stack whose root pushes the app's own `Allow` page, each screen able to raise the sheets on a tap.
private struct OwnAllowRoot: View {
    @State private var answered = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                NavigationLink("Show own page") {
                    OwnAllowPage(answered: $answered)
                }
                AskButton(answered: $answered)
            }
            .navigationTitle("Fixture")
        }
    }
}

/// The app's own page: a button labelled and identified as a sheet's would be, which does nothing.
private struct OwnAllowPage: View {
    @Binding var answered: Bool

    var body: some View {
        VStack(spacing: 24) {
            Button("Allow") {}
                .accessibilityIdentifier("own-allow")
            AskButton(answered: $answered)
        }
        .navigationTitle("Own page")
    }
}

/// Raises the two sheets, and says so once both have been answered.
private struct AskButton: View {
    @Binding var answered: Bool

    var body: some View {
        if answered {
            Text("Both permissions answered")
                .accessibilityIdentifier("permissions-answered-label")
        } else {
            Button("Ask for permissions") {
                Task {
                    await askForBoth()
                    answered = true
                }
            }
        }
    }
}

/// Answered, not granted: the screen appears whatever the person chose, because what a walk proves is that it reached and cleared each sheet.
private func askForBoth() async {
    try? await Task.sleep(for: .seconds(1))
    let steps = HKQuantityType(.stepCount)
    try? await HKHealthStore().requestAuthorization(toShare: [steps], read: [steps])
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
}
