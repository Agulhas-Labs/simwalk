//
// Copyright © Agulhas Labs
//

import SwiftUI

/// The demo's first screen: an "Account" list of title and value rows, ending in a link to the usage screen.
struct AccountScreen: View {
    private let rows: [(title: LocalizedStringKey, value: LocalizedStringKey)] = [
        ("Storage", "12.4 GB of 50 GB"),
        ("Notifications", "On, with previews"),
        ("Language", "English (United Kingdom)"),
        ("Plan", "Family, 5 members"),
        ("Backups", "Daily at 02:00"),
    ]

    private let regression = UserDefaults.standard.bool(forKey: "SimWalkDemoRegression")
    private let truncation = UserDefaults.standard.bool(forKey: "SimWalkDemoTruncation")

    var body: some View {
        NavigationStack {
            List {
                ForEach(0 ..< rows.count, id: \.self) { index in
                    AccountRow(
                        title: rows[index].title,
                        value: rows[index].value,
                        regression: regression,
                        truncation: truncation,
                        identifier: "row-title-\(index)"
                    )
                }
                NavigationLink("Usage") { UsageScreen() }
            }
            .accessibilityIdentifier("account-list")
            .navigationTitle("Account")
        }
        .accessibilityIdentifier("account-screen")
    }
}
