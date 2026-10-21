//
// Copyright © Agulhas Labs
//

import CoreLocation
import SwiftUI

/// A generic subject for the walk's route steps and capture states: a home screen and the screens a URL can reach from it.
///
/// `simwalk-fixture://detail` opens the detail screen and `simwalk-fixture://location` the location screen and `simwalk-fixture://banner` the banner screen; any other URL leaves the app on home. Home carries a horizontal run of three texts, which is what a `layoutDirection` state is judged by: right to left in tree order under `rtl`.
@main
struct RouteFixtureApp: App {
    @State private var path: [Route] = []

    init() {
        if ProcessInfo.processInfo.arguments.contains("-RouteFixtureResetErased") {
            UserDefaults.standard.removeObject(forKey: "RouteFixtureErased")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-RouteFixtureTabs") {
                TabsRoot()
            } else {
                stackRoot
            }
        }
    }

    private var stackRoot: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Text("Home")
                HStack(spacing: 16) {
                    Text("First")
                    Text("Second")
                    Text("Third")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route-home")
            .navigationTitle("Home")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail:
                    Text("Detail")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("route-detail")
                        .navigationTitle("Detail")
                case .location:
                    LocationScreen()
                case .banner:
                    BannerScreen()
                }
            }
        }
        .onOpenURL { url in
            path = Route(url: url).map { [$0] } ?? []
        }
    }
}

/// A screen a URL can reach.
private enum Route: Hashable {
    case detail
    case location
    case banner

    /// The screen `url` names, or `nil` for one the fixture does not route.
    init?(url: URL) {
        guard url.scheme == "simwalk-fixture" else { return nil }
        switch url.host() {
        case "detail":
            self = .detail
        case "location":
            self = .location
        case "banner":
            self = .banner
        default:
            return nil
        }
    }
}

/// Asks for when-in-use location and shows the first coordinate it is given, to two decimal places — what a `location` state is verified by — on a screen identified as `location-value`.
///
/// Until a coordinate arrives the screen is identified as `location-pending` instead, so a capture that settled before the fix cannot pass `expect: "location-value"`. The identifier is the screen's, not the text's, because `expect` is held to a screen's own identifier (`ScreenIdentifierRule`), the first stable one in the tree.
private struct LocationScreen: View {
    @State private var manager = CLLocationManager()
    @State private var shown: String?

    var body: some View {
        Group {
            if let shown {
                Text(shown)
            } else {
                Text("Locating")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(shown == nil ? "location-pending" : "location-value")
        .navigationTitle("Location")
        .task {
            manager.requestWhenInUseAuthorization()
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let location = update.location else { continue }
                    shown = String(format: "%.2f, %.2f", location.coordinate.latitude, location.coordinate.longitude)
                    break
                }
            } catch {
                shown = nil
            }
        }
    }
}

/// A few rows that a banner pushes down three seconds after the screen appears — late enough that XCUITest's `open`, which has been seen to wait past a one-second banner, returns before it — the layout shift `motion.walkbook.json` walks (SimWalk#67, M2): the shift is the rows', caused by the banner's insertion, and not the push that brought the page in.
private struct BannerScreen: View {
    @State private var showsBanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showsBanner {
                    Text("Offline mode is on")
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(.yellow)
                        .accessibilityIdentifier("banner")
                }
                ForEach(1 ... 4, id: \.self) { row in
                    Text("Row \(row)")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-banner")
        .navigationTitle("Banner")
        .task {
            try? await Task.sleep(for: .seconds(3))
            showsBanner = true
        }
    }
}
