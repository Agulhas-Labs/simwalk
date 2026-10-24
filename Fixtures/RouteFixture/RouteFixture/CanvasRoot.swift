//
// Copyright © Agulhas Labs
//

import SwiftUI

/// The canvas mode (`-RouteFixtureCanvas`): one full-screen colour with nothing a reader lists, which flips between two colours on every tap — the shape of a game drawn into a single Metal view, whose accessibility tree has no text for the screen hash to go on (SimWalk#150).
struct CanvasRoot: View {
    @State private var flipped = false

    var body: some View {
        (flipped ? Color.white : Color.black)
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onTapGesture { flipped.toggle() }
    }
}
