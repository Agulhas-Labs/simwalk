//
// Copyright © Agulhas Labs
//

/// Which accessibility identifiers in a capture can name its screen — the exclusions `ScreenIdentifier` reads a screen's identifier under (the `bundle screen` feature), restated as the smallest rule `expect` needs until the two collapse into that one type.
///
/// **What does not count, exactly.** A tree is rooted at the `Application` element, which XCUITest never identifies, so only what lies beneath it is read — and three things beneath it are not:
/// - **A bar and everything in it**: `NavigationBar`, `Toolbar`, `TabBar` (``ScreenContentCheck/chromeTypes``). They are the app's frame, not a screen: a tab bar's items carry their SF Symbol names (`person.fill`, `list.bullet`) on every screen the bar appears on, a toolbar carries the literal `Toolbar`, and a pushed screen's back button `BackButton`. **That includes the navigation bar's own identifier**, which is its title: a title is localised and not unique, so an `expect` naming one would flip under a `loc_fr_fr` state and pass on any other screen titled the same. ``navigationBarTitle(of:)`` reads it only so a mismatch can say that is what happened.
/// - **An element-level node and everything in it** (``elementTypes``): an image's identifier is its asset or symbol name, and a control's or a text's names that one element rather than the screen around it.
/// - **A Swift-mangled runtime class name** (`_Tt…`), which names a framework's type rather than anything the app chose — SwiftUI's `_TtGC7SwiftUI32NavigationStackHosting` sits on every pushed screen.
///
/// An `expect` naming any of those would pass on every screen, so none of them is evidence of having reached one. What is left is a container's identifier — on a real capture, the scroll view the app identifies as the screen.
///
/// **Not restated here, two things `ScreenIdentifier` does beyond this.** Its presentation scope, which reads only the topmost sheet or alert when one covers the screen — no capture this tool has taken holds a presentation, so the scope arrives with that type when this is replaced by it. And the navigation-bar title it may *display* for a screen whose content carries no identifier: a title is never a stable identifier, and a stable identifier is the only thing `expect` is compared against.
public struct ScreenIdentifierRule {
    /// The node types whose identifier names one element rather than a screen, and whose subtrees are that element's parts — as ``AXNode/type`` spells them.
    ///
    /// The same set as `ScreenIdentifier.elementTypes`.
    public static let elementTypes: Set<String> = [
        "Image", "StaticText", "Button", "Link", "Switch", "Slider", "TextField", "SecureTextField", "TextView", "Cell",
    ]

    /// Whether neither `node`'s own identifier nor any identifier beneath it can name a screen: it is a bar (``ScreenContentCheck/chromeTypes``) or an element-level node (``elementTypes``).
    ///
    /// A property of the whole subtree, not of the node alone — a tab bar's button is excluded because it sits under the bar, whatever its own type.
    public static func isChrome(_ node: AXNode) -> Bool {
        ScreenContentCheck.chromeTypes.contains(node.type) || elementTypes.contains(node.type)
    }

    /// Whether `identifier` can name anything an app chose: not blank, and not a Swift-mangled runtime class name (`_Tt…`).
    public static func isUsable(_ identifier: String) -> Bool {
        !identifier.isEmpty && !identifier.hasPrefix(mangledPrefix)
    }

    /// Every identifier in `tree` that can name its screen, in tree order: each usable identifier beneath the root that no ``isChrome(_:)`` node encloses.
    public static func screenLevelIdentifiers(in tree: AXNode) -> [String] {
        tree.children.flatMap(identifiers(within:))
    }

    /// The stable identifier `tree`'s screen is known by — the first of ``screenLevelIdentifiers(in:)`` — or `nil` when its content carries none.
    ///
    /// Never the navigation bar's title, even when nothing else names the screen: `nil` is the honest answer there, and what a mismatch reports.
    public static func screenIdentifier(of tree: AXNode) -> String? {
        screenLevelIdentifiers(in: tree).first
    }

    /// What a mismatch's `found` reports for `tree`: the screen-level identifiers on the path to the deepest one, outer to inner, joined by ` > ` (`parent > controls`), or `nil` when the tree carries none.
    ///
    /// **The deepest** is the screen-level identifier with the most ancestors, the first in tree order at a tie; the path is every screen-level identifier on its ancestor chain, itself included. When none nests inside another every one is deepest and the first wins, so the entry is the single identifier ``screenIdentifier(of:)`` names. It is what an author reading a missed `expect` needs: a view's identifier set on a container replaces those of the views inside it, so the identifier the app meant for the screen's content is often the nested one.
    public static func foundPath(of tree: AXNode) -> String? {
        deepestPath(of: tree).map { $0.joined(separator: pathSeparator) }
    }

    /// The sentence a mismatch's `reason` gains when ``foundPath(of:)`` holds more than one identifier — naming the deepest and why it may not be the one the author set — or `nil` when it holds one or none.
    public static func deepestIdentifierClause(of tree: AXNode) -> String? {
        guard let path = deepestPath(of: tree), path.count > 1 else { return nil }
        return "the deepest identifier is '\(path[path.count - 1])'; an identifier set on a container replaces those of the views inside it"
    }

    /// Whether `tree` is of the screen `expect` names: any of its ``screenLevelIdentifiers(in:)`` equals it.
    ///
    /// **Any screen-level identifier, outermost or nested** (SimWalk#103). A screen hosted inside another's content carries both names (a screen's content view wraps the block, each with its own `_screen`), and so does an iPad split view, whose sidebar comes first; comparing only the first refused correct screens. It guards nothing the any-match lets through, because a wrong screen does not carry the expected identifier anywhere. A mismatch's `found` names the path to the deepest one instead (``foundPath(of:)``). Chrome, element-level identifiers and mangled names never count, as in ``screenLevelIdentifiers(in:)``.
    public static func carries(_ expect: String, in tree: AXNode) -> Bool {
        screenLevelIdentifiers(in: tree).contains(expect)
    }

    /// The first node outside the bars (``ScreenContentCheck/chromeTypes``) that carries `identifier` and is not a container (``ScreenIdentifier/containerTypes``) — a text, a control, an image — with the nearest screen-level identifier enclosing it (`nil` when none does), or `nil` when no such node exists.
    ///
    /// Never evidence that a tree is of a screen (``carries(_:in:)`` still refuses it); read only so a mismatch can say the identifier sits on an element, not a screen container.
    public static func elementCarrying(_ identifier: String, in tree: AXNode) -> (type: String, enclosing: String?)? {
        func visit(_ node: AXNode, enclosing: String?, insideElement: Bool) -> (type: String, enclosing: String?)? {
            guard !ScreenContentCheck.chromeTypes.contains(node.type) else { return nil }
            let own = node.identifier.flatMap { isUsable($0) ? $0 : nil }
            if own == identifier, !ScreenIdentifier.containerTypes.contains(ScreenIdentifier.canonicalType(node.type)) {
                return (node.type, enclosing)
            }
            let inElement = insideElement || elementTypes.contains(node.type)
            let next = (inElement ? nil : own) ?? enclosing
            for child in node.children {
                if let hit = visit(child, enclosing: next, insideElement: inElement) {
                    return hit
                }
            }
            return nil
        }
        for child in tree.children {
            if let hit = visit(child, enclosing: nil, insideElement: false) {
                return hit
            }
        }
        return nil
    }

    /// The first navigation bar's usable identifier — its title — or `nil` when no bar carries one.
    ///
    /// Never evidence of which screen a tree is (the bar is chrome); read only so a mismatch can say that the value `expect` names is this screen's title, which is the one mistake a reader copying `found` from a title-only screen would otherwise make.
    public static func navigationBarTitle(of tree: AXNode) -> String? {
        navigationBarIdentifier(among: tree.children)
    }
}

private extension ScreenIdentifierRule {
    /// How the Swift runtime begins a mangled class name.
    static var mangledPrefix: String {
        "_Tt"
    }

    static var pathSeparator: String {
        " > "
    }

    /// The identifiers on the ancestor chain of the deepest screen-level identifier, outer to inner, itself last.
    static func deepestPath(of tree: AXNode) -> [String]? {
        var best: (depth: Int, path: [String])?
        func visit(_ node: AXNode, depth: Int, path: [String]) {
            guard !isChrome(node) else { return }
            var path = path
            if let own = node.identifier, isUsable(own) {
                path.append(own)
                if best.map({ depth > $0.depth }) ?? true {
                    best = (depth, path)
                }
            }
            for child in node.children {
                visit(child, depth: depth + 1, path: path)
            }
        }
        for child in tree.children {
            visit(child, depth: 1, path: [])
        }
        return best?.path
    }

    static func identifiers(within node: AXNode) -> [String] {
        guard !isChrome(node) else { return [] }
        let own = node.identifier.flatMap { isUsable($0) ? [$0] : nil } ?? []
        return own + node.children.flatMap(identifiers(within:))
    }

    /// The first navigation bar's usable identifier among `nodes`, looking through everything but the other bars.
    static func navigationBarIdentifier(among nodes: [AXNode]) -> String? {
        for node in nodes {
            if node.type == navigationBarType {
                if let identifier = node.identifier, isUsable(identifier) {
                    return identifier
                }
            } else if !ScreenContentCheck.chromeTypes.contains(node.type), let found = navigationBarIdentifier(among: node.children) {
                return found
            }
        }
        return nil
    }

    static var navigationBarType: String {
        "NavigationBar"
    }
}
