//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a capture holds a screen at all, or only the frame the app draws around one.
///
/// **A spinner holds still, and stillness is what the settle window rewards.** A real app's Browse tab takes one to three seconds to populate on a cold visit; at the default quiet period its capture is a bare spinner with an accessibility tree carrying nothing but the tab bar, filed as `captured` with `axTreeSettled: true` — a perfectly true statement about the tree and a perfectly false impression of the screen (SimWalk#7). A loading tree is *more* still than a real one, so no timing threshold separates them.
///
/// **This is a content check, so a slow machine cannot defeat it.** It asks what the capture holds rather than how long the runner waited: a tree whose only labels belong to the tab bar is a screen that has not arrived, on any machine, at any settle.
///
/// **It flags rather than refuses**, and that is the whole difference from `StateApplicationCheck`. A state the device discarded produces evidence that cannot be attributed to anything, so nothing may be filed; a screen that had not populated produces an entirely honest picture of a screen mid-load — worth keeping, worth reading, and worth not mistaking for the screen itself. The flag rides `CaptureManifest.StateCapture.axTreeHasContent` and moves the walk's exit code, exactly as an unsettled capture does.
public struct ScreenContentCheck {
    /// The container types whose subtrees are the app's frame rather than one screen's content.
    ///
    /// A tab bar and a navigation bar are present on the loading state and on the loaded one alike, so neither can distinguish them; a navigation title is chrome for the same reason — a pushed screen shows its title before it has anything under it.
    public static let chromeTypes: Set<String> = ["TabBar", "NavigationBar", "Toolbar"]

    /// Whether this capture holds the app's chrome and nothing else.
    public static func isChromeOnly(_ tree: AXNode) -> Bool {
        contentLabels(in: tree).isEmpty
    }

    /// The labels this capture holds that belong to a screen rather than to the app's frame, in tree order.
    ///
    /// **The root's own label is not content**, because it is the application's name — the app's name sits at the top of every tree this tool has ever taken, loading or loaded, so counting it would make the check vacuous on precisely the specimen it was built from.
    ///
    /// Labels rather than values: the spinner in that specimen carries a `value` of `1` and no label, and a check that counted values would read the loading indicator itself as the content it exists to notice was missing.
    public static func contentLabels(in tree: AXNode) -> [String] {
        tree.children.flatMap(labels(in:))
    }

    private static func labels(in node: AXNode) -> [String] {
        guard !chromeTypes.contains(node.type) else { return [] }
        return (node.label.map { [$0] } ?? []) + node.children.flatMap(labels(in:))
    }
}
