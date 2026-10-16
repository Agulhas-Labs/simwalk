//
// Copyright © Agulhas Labs
//

import SwiftUI

/// A sailing log on fixed data: a subject for the segmenter, one screen per shape of section it has to read.
///
/// Three tabs: `Log` (a summary), `Passages` (a week's list, whose first row opens a passage's detail) and `Boat` (three detail screens, one per axis style). `-SegmenterFixtureLaterWeek` swaps the week the list shows.
@main
struct SegmenterFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Log", systemImage: "book.closed") {
                    SummaryScreen()
                }
                Tab("Passages", systemImage: "sailboat") {
                    NavigationStack {
                        PassagesScreen(week: LogData.week)
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: String.self) { _ in
                                PassageDetailScreen()
                            }
                    }
                }
                Tab("Boat", systemImage: "gauge.with.dots.needle.33percent") {
                    NavigationStack {
                        BoatScreen()
                    }
                }
            }
        }
    }
}

/// The `Boat` tab: a link to each of the three chart screens.
struct BoatScreen: View {
    var body: some View {
        List {
            NavigationLink("Wind") { WindScreen() }
            NavigationLink("Hours afloat") { HoursAfloatScreen() }
            NavigationLink("Anchor watch") { AnchorWatchScreen() }
        }
        .navigationTitle("Boat")
    }
}
