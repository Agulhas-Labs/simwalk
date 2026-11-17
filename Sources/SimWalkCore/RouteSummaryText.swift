//
// Copyright © Agulhas Labs
//

import Foundation

/// How a route is printed on an answer line (SimWalk#256): a long route is named by what it shares with an earlier screen, or by its ends.
///
/// A 117-step route costs about a thousand tokens per screen and a reader greps the residue away to avoid it, which is how a dry run's DRIFTED line went unseen (SimWalk#260). The full route stays in the manifest, in `result.json` under `--verbose` and in the dry run's report; `rendered` is that spelling.
struct RouteSummaryText {
    /// Up to this many steps print in full.
    ///
    /// Four steps cost less to print than the short form saves, and it keeps every route the README and Reference show (three steps at most) spelled as they are.
    static let fullRouteLimit = 4

    /// `route` as an answer line prints it.
    ///
    /// `earlier` holds only screens that reached their screen, so a prefix reference never names a route that stopped short.
    ///
    /// **The reference is the earlier screen sharing the longest leading run of steps**: its whole route, or, when the route turns off it, a run longer than a route printed in full (`complete's first 117 steps + tap 'Done' → …`). Matching whole routes only, two screens that branch late off one journey (a field walkbook's `complete` and `home-after`, 117 of 119 steps shared and the same last step) printed one line between them, with the step that tells them apart hidden in the `…`.
    static func text(of route: [Walkbook.RouteStep], after earlier: [(id: String, route: [Walkbook.RouteStep])]) -> String {
        guard route.count > fullRouteLimit else { return route.rendered }
        let runs: [SharedRun] = earlier.map { SharedRun(id: $0.id, whole: $0.route.count, length: sharedLength(route, $0.route)) }
        let shared = runs.filter(\.isWorthNaming).max { $0.rank < $1.rank }
        guard let shared else {
            return "\(route.count) steps: \(route[0].description) … \(route[route.count - 1].description)"
        }
        let start = shared.length == shared.whole ? shared.id : "\(shared.id)'s first \(shared.length) steps"
        guard shared.length < route.count else {
            return shared.length == shared.whole ? "\(shared.id)'s route" : start
        }
        return "\(start) + \(text(of: Array(route.dropFirst(shared.length)), after: []))"
    }

    /// How many leading steps `route` and `other` have in common.
    private static func sharedLength(_ route: [Walkbook.RouteStep], _ other: [Walkbook.RouteStep]) -> Int {
        zip(route, other).prefix { $0 == $1 }.count
    }
}

private extension RouteSummaryText {
    /// The leading steps a route shares with one earlier screen's.
    struct SharedRun {
        let id: String
        /// How many steps the earlier screen's route has.
        let whole: Int
        /// How many leading steps the two routes share.
        let length: Int

        /// A whole earlier route is worth naming however short; part of one only when the part is longer than a route printed in full.
        var isWorthNaming: Bool {
            length > 0 && (length == whole || length > RouteSummaryText.fullRouteLimit)
        }

        /// The longest run wins, and at an equal run a whole route, whose name alone says what was shared.
        var rank: Int {
            length * 2 + (length == whole ? 1 : 0)
        }
    }
}

extension [Walkbook.RouteStep] {
    /// The route as an answer line prints it; see ``RouteSummaryText``.
    func summarized(after earlier: [(id: String, route: [Walkbook.RouteStep])]) -> String {
        RouteSummaryText.text(of: self, after: earlier)
    }
}
