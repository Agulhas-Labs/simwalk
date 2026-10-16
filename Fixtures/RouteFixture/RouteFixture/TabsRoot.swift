//
// Copyright © Agulhas Labs
//

import SwiftUI

/// The tabs mode (`-RouteFixtureTabs`): a sidebar-adaptable `TabView` with one tab per walk-behaviour shape `tabs.walkbook.json` walks — the floating bottom bar on iPhone, the floating top bar on iPad. Launches on Hub.
struct TabsRoot: View {
    var body: some View {
        TabView {
            Tab("Hub", systemImage: "house") { HubScreen() }
            Tab("Rows", systemImage: "list.bullet") { RowsScreen() }
            Tab("Menus", systemImage: "filemenu.and.selection") { MenusScreen() }
            Tab("Nested", systemImage: "square.stack") { NestedScreen() }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Twenty plain rows and then `Open form`, below the fold on iPhone — SimWalk#104 (a tap right after a push) and SimWalk#106 (a launch-argument deep link, `-RouteFixturePushForm`, that pushes the form on first appearance).
private struct HubScreen: View {
    @State private var path: [HubRoute] = []
    @State private var pushedOnLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(1 ... 20, id: \.self) { Text("Hub row \($0)") }
                NavigationLink("Open form", value: HubRoute.form)
            }
            .accessibilityIdentifier("hub-screen")
            .navigationTitle("Hub")
            .navigationDestination(for: HubRoute.self) { _ in FormScreen() }
        }
        .onAppear {
            guard !pushedOnLaunch, ProcessInfo.processInfo.arguments.contains("-RouteFixturePushForm") else { return }
            pushedOnLaunch = true
            path = [.form]
        }
    }
}

private enum HubRoute: Hashable {
    case form
}

/// The form Hub pushes, in the shape of the real app's: a pushed `Form` with an inline title and an `Add entry` button that opens a sheet identified `form-sheet` — SimWalk#104, #106.
private struct FormScreen: View {
    @State private var showsSheet = false

    var body: some View {
        Form {
            Section { ForEach(1 ... 3, id: \.self) { Text("Entry \($0)") } }
            Section { Button("Add entry") { showsSheet = true }.accessibilityIdentifier("form-add") }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("Form")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("form-screen")
        .sheet(isPresented: $showsSheet) {
            Text("Sheet")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("form-sheet")
        }
    }
}

/// A row that starts about 24 pt above the bottom of the safe area, so most of it sits under the floating tab bar at launch — SimWalk#108 (`scrollTo` must not settle the target still overlapping the tab bar).
private struct RowsScreen: View {
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(0, proxy.size.height - 24))
                        Text("Partly covered row")
                            .frame(maxWidth: .infinity, minHeight: 60)
                        ForEach(1 ... 30, id: \.self) { row in
                            Text("Filler row \(row)")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rows-screen")
            .navigationTitle("Rows")
        }
    }
}

/// A `Menu` whose open popover the tree does not carry under any identifier — SimWalk#111 (`expect` after a tap that opens a menu).
private struct MenusScreen: View {
    var body: some View {
        NavigationStack {
            VStack {
                Menu("Kind") {
                    Button("Endurance") {}
                    Button("Walking") {}
                    Button("Strength") {}
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menus-screen")
            .navigationTitle("Menus")
        }
    }
}

/// An identified scroll view holding an identified container — SimWalk#103 (both identifiers must reach the tree on non-element nodes, outer first).
private struct NestedScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Outer heading")
                    VStack(alignment: .leading) {
                        Text("Inner body")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nested-inner")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .accessibilityIdentifier("nested-outer")
            .navigationTitle("Nested")
        }
    }
}
