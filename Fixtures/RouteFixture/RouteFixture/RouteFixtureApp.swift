//
// Copyright © Agulhas Labs
//

import CoreLocation
import SwiftUI

/// A generic subject for the walk's route steps and capture states: a home screen and the screens a URL can reach from it.
///
/// `simwalk-fixture://detail` opens the detail screen and `simwalk-fixture://location` the location screen and `simwalk-fixture://banner` the banner screen and `simwalk-fixture://pulse` the pulse screen; any other URL leaves the app on home. Home carries a horizontal run of three texts, which is what a `layoutDirection` state is judged by: right to left in tree order under `rtl`.
@main
struct RouteFixtureApp: App {
    @UIApplicationDelegateAdaptor private var delegate: OrientationDelegate
    @State private var path: [Route] = []
    @State private var strategyDone = false

    init() {
        if ProcessInfo.processInfo.arguments.contains("-RouteFixtureResetErased") {
            UserDefaults.standard.removeObject(forKey: "RouteFixtureErased")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-RouteFixtureLandscapeOnly") {
                LandscapeOnlyRoot()
            } else if ProcessInfo.processInfo.arguments.contains("-RouteFixtureCanvas") {
                CanvasRoot()
            } else if ProcessInfo.processInfo.arguments.contains("-RouteFixtureTabs") {
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
                Button("Values") { path.append(.values) }
                Button("Loading") { path.append(.loading) }
                Button("Stalled") { path.append(.stalled) }
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
                case .pulse:
                    PulseScreen()
                case .values:
                    ValuesList(path: $path, done: strategyDone)
                case .strategy:
                    StrategyDetail(path: $path, done: $strategyDone)
                case .loading:
                    LoadingScreen(loadsAfter: .seconds(3))
                case .stalled:
                    LoadingScreen(loadsAfter: nil)
                }
            }
        }
        .onOpenURL { url in
            path = Route(url: url).map { [$0] } ?? []
        }
    }
}

/// Holds the app to portrait under `-RouteFixturePortraitOnly`, which is what an `orientation` state asking for landscape is refused by (SimWalk#199); otherwise the orientations the Info.plist lists, `.all` on an iPad and everything but upside down on an iPhone.
private final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        if ProcessInfo.processInfo.arguments.contains("-RouteFixturePortraitOnly") {
            return .portrait
        }
        if ProcessInfo.processInfo.arguments.contains("-RouteFixtureLandscapeOnly") {
            return .landscape
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }
}

/// A screen a URL can reach.
private enum Route: Hashable {
    case detail
    case location
    case banner
    case pulse
    case values
    case strategy
    case loading
    case stalled

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
        case "pulse":
            self = .pulse
        default:
            return nil
        }
    }
}

/// A list whose one row reads its state as an accessibility value, the shape `expectValues` checks (SimWalk#259): "Choosing a strategy" reads `Start` until the detail screen's `Save` marks it `Done`. Reached from home by tapping `Values`.
///
/// Every tap on this specimen navigates, because a value change alone does not count as a landed tap. The state is held in memory by the app, so a relaunch starts every walk at `Start`.
private struct ValuesList: View {
    @Binding var path: [Route]
    let done: Bool

    var body: some View {
        List {
            Button("Choosing a strategy") { path.append(.strategy) }
                .accessibilityValue(done ? "Done" : "Start")
        }
        .accessibilityIdentifier("values-list")
        .navigationTitle("Strategies")
    }
}

/// The detail screen of the `ValuesList` row: `Save` marks it done and pops back to the list.
private struct StrategyDetail: View {
    @Binding var path: [Route]
    @Binding var done: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("Choosing a strategy")
            Button("Save") {
                done = true
                path.removeLast()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("values-detail")
        .navigationTitle("Strategy")
    }
}

/// A sheet-like screen whose content follows a labelled loading state, the shape SimWalk#267 was found on: a title and a `ProgressView` labelled "Loading the answer…" until `loadsAfter` has passed, then two sentences and `Done`. `nil` never loads, for a capture that is still loading when the content wait runs out. Reached from home by tapping `Loading` or `Stalled`.
///
/// The screen's identifier is the same in both states, so `expect` passes on either: what tells them apart is what the capture holds, which is the point of the specimen.
private struct LoadingScreen: View {
    let loadsAfter: Duration?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Another way to see it")
            if loaded {
                Text("The answer is 15.5.")
                Text("Add the whole numbers, then the tenths.")
                Button("Done") {}
            } else {
                ProgressView {
                    Text("Loading the answer…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loading-screen")
        .navigationTitle("Explain")
        .task {
            guard let loadsAfter else { return }
            try? await Task.sleep(for: loadsAfter)
            loaded = true
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

/// Three SwiftUI animations that keep running during a walk, which SimWalk's UIKit animations-off does not stop: buttons that pulse forever (SimWalk#252, #253, #258), answer tiles whose only effect is a trait change (#251), and a feedback panel that slides in on a spring (#255). `pulse.walkbook.json` walks them.
///
/// "Start" and "Far node" (below the fold) show a text when tapped; "4" and "6" select, which changes nothing but the `isSelected` trait; "Check" slides the panel in and its "Continue" changes the **container's** identifier to `route-pulse-done`, which is what `expect` reads (`ScreenIdentifierRule`).
private struct PulseScreen: View {
    @State private var started = false
    @State private var farOpened = false
    @State private var selected: Int?
    @State private var showsPanel = false
    @State private var done = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pulsing("Start") { started = true }
                if started {
                    Text("Started").accessibilityIdentifier("pulse-started")
                }
                HStack(spacing: 16) {
                    tile(4)
                    tile(6)
                }
                Button("Check") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showsPanel = true }
                }
                .disabled(selected == nil)
                Color.clear.frame(height: 900)
                pulsing("Far node") { farOpened = true }
                if farOpened {
                    Text("Far node opened")
                }
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if showsPanel {
                VStack {
                    Text("Correct")
                    Button("Continue") { done = true }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
                .transition(.move(edge: .bottom))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(done ? "route-pulse-done" : "route-pulse")
        .navigationTitle("Pulse")
    }

    /// A button that pulses forever.
    private func pulsing(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .phaseAnimator([1.0, 1.06]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .easeInOut(duration: 0.6)
            }
    }

    /// An answer tile; selecting it changes only its `isSelected` trait.
    private func tile(_ value: Int) -> some View {
        Button("\(value)") { selected = value }
            .buttonStyle(.bordered)
            .accessibilityAddTraits(selected == value ? .isSelected : [])
    }
}

/// A landscape-only app's screen under `-RouteFixtureLandscapeOnly` (SimWalk#222): one button at a fixed place, so its centre is the same landscape point on every iPad, 120 pt across and 160 pt down from the app frame's top-left.
///
/// Tapping it changes the **container's** identifier, which is what a walkbook's `expect` reads. A tap that lands elsewhere (the portrait grid's reading of that point) leaves it `route-home`.
private struct LandscapeOnlyRoot: View {
    @State private var tapped = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Button("Landscape target") { tapped = true }
                .frame(width: 160, height: 80)
                .background(Color.blue.opacity(0.3))
                .padding(.leading, 40)
                .padding(.top, 120)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(tapped ? "route-home-landscape-tapped" : "route-home")
    }
}
