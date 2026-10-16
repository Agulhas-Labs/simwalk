//
// Copyright © Agulhas Labs
//

/// The accessibility identifier a capture's screen is known by, and where on the tree it was read — the answer to "which screen did this step reach" that `bundle screen` prints and walkbook `expect:` compares against.
///
/// Not `ScreenIdentity`, which compares two trees' whole structure to tell whether a step left a screen; this names one screen by the one string an app sets for it, where it sets one. **It answers only what the tree states outright, and `nil` where it does not** — `expect:` trusts it, and a wrong answer passes `expect:` on the wrong screen where `nil` only fails it. The runner roots every tree at the application element, which XCUITest never identifies, so the identifier is looked for beneath it:
///
/// 1. **Scope: the topmost presentation, else the app's window.** The app's window is the first window in tree order. A window holding a keyboard is chrome and never looked inside. A presentation is a node XCUITest types as one — `Alert`, `Sheet` (an action sheet or confirmation dialog), `Popover` — or a **page sheet**, told by the shape UIKit gives one: a view reaching past the screen on every edge (the dimming view), followed among its siblings by the sheet's container, whose own children include a button labelled `Sheet Grabber`. Presentations are looked for through containers (``containerTypes``) in the app's window and every later window but a keyboard's; the last one in tree order is the topmost, since tree order is back to front, and it is not looked inside for another. When there is one, only it is read, so a covered screen's identifier never answers for it; when there is none, only the app's window is — a toast's window never names the screen.
/// 2. **Content.** The first identifier in tree order on a **container** — a node whose type is in ``containerTypes`` — looking inside containers only. An element's, a control's, chrome's and a type the core does not know as a container (the runner's raw `TypeNN` for a type it did not name) are never read, and neither are their insides: an image's identifier is its asset or symbol name, and a control's names that control. An identifier a framework set is refused wherever it appears: a Swift-mangled class name (`_Tt…`), an underscore-private one (`_UI…`), and the ones in ``frameworkIdentifiers``. What is left is a container's identifier — on a real capture, the scroll view or list the app identifies as the screen — reported as ``Source/content``, the only source ``AXNode/screenIdentifier`` returns.
/// 3. **Only when asked, and only when no container carries one: two identifiers that are no stable identity.** First the navigation bar's title — the identifier of the first navigation bar in scope, under the same framework rules — as ``Source/navigationBar``: a bar's identifier is its **localised** title, so it changes with the device's language. Then an identifier SwiftUI propagated, as ``Source/propagated``: `.accessibilityIdentifier` on a plain stack lands on every element inside it rather than on a node of its own, so an identifier carried by every element-level child of one container — at least two, not all images, no cells — is reported; but a shared row identifier has the same shape, so it may name the rows rather than the screen.
///
/// Neither other bar is ever read: a toolbar carries the literal `Toolbar` on every screen, and a tab bar's identifiers are its items'. Nothing found is `nil`, never a guess.
///
/// **What it does not recognise, by design.** An overlay that keeps the covered screen in the tree and carries no presentation type is not a presentation: a toast, a HUD, a banner or a loading overlay is read with the screen, so the covered screen's identifier answers under it. A page sheet without its grabber — or whose grabber's label is not the English `Sheet Grabber` — is not recognised as presented; every real page sheet captured took the covered screen out of the tree, so its own content is still what is read, and only ``isPresented`` is wrong. A presentation held inside another's node is read as part of the outer one.
///
/// **Checked against real captures.** On an iOS 26.5 simulator: the keyboard — two windows after the app's, one holding the input view's empty host (`inputView`), the other the typing-predictions bar, the keys under a keyboard node and the emoji and dictation buttons, or on a keyboard's first use the continuous-path introduction in place of the keys; a page sheet, held inside the app's window after its dimming view, with the covered screen gone from the tree; and a confirmation dialog shown as a popover — XCUITest's `PopoverDismissRegion`, then a popover node holding a `Sheet`, the covered screen again gone. Also the 42 captures of one SwiftUI app, which present nothing. An `Alert`-typed node and a presentation in a window of its own are reasoned, not captured.
public struct ScreenIdentifier: Equatable, Sendable {
    /// The identifier itself.
    public let value: String

    /// Where on the tree it was read.
    public let source: Source

    /// Whether it was read inside a presentation over the screen: a node XCUITest types `Alert`, `Sheet` or `Popover`, or a page sheet by its shape — a view reaching past the screen on every edge, then the sheet's container holding its `Sheet Grabber` button.
    public let isPresented: Bool

    /// The node types whose own identifier can name a screen, and the only ones looked inside for one — as ``AXNode/type`` spells them: the plain and scrolling containers, the window, and the three presentation types.
    public static let containerTypes: Set<String> = [
        "Other", "Group", "LayoutArea", "ScrollView", "Table", "CollectionView", "Window", "Sheet", "Alert", "Popover",
    ]

    /// Identifiers the system sets on its own regions, refused wherever they appear: a popover's dismiss barrier, and the keyboard's input host, predictions bar and its page — every one seen on a real capture.
    public static let frameworkIdentifiers: Set<String> = ["PopoverDismissRegion", "inputView", "SystemInputAssistantView", "CenterPageView"]

    public init(value: String, source: Source, isPresented: Bool = false) {
        self.value = value
        self.source = source
        self.isPresented = isPresented
    }

    /// The identifier `tree`'s screen is known by, or `nil` when nothing in scope carries a usable one — the steps above.
    ///
    /// - Parameters:
    ///   - tree: a capture's whole tree, rooted at the application element.
    ///   - fallingBackToUnstable: whether, when no container carries an identifier, a navigation bar's title and then a propagated identifier may answer. Off by default: neither is an identity a comparison can hold to — a title changes with the language a walk captures in, and a propagated identifier may name the rows it was copied onto.
    public init?(of tree: AXNode, fallingBackToUnstable: Bool = false) {
        guard let found = Self.reading(tree, fallingBackToUnstable: fallingBackToUnstable).identifier else { return nil }
        self = found
    }
}

public extension ScreenIdentifier {
    /// Where the identifier was read.
    enum Source: Equatable, Sendable {
        /// A container's own identifier, in the screen's content or the presentation's — the only stable source.
        case content
        /// A navigation bar's own identifier — its localised title — because no container carried one and a fallback was asked for.
        case navigationBar
        /// The identifier every element-level child of one container carries — SwiftUI's propagation of a container's modifier, or a shared row identifier; no container carried one and a fallback was asked for.
        case propagated
    }
}

extension ScreenIdentifier {
    /// What one read of a tree found: the identifier, the presentation it was read in, and the framework identifiers refused on the way — kept together so a caller that has to say why there is none reads the tree once.
    struct Reading: Equatable {
        let identifier: ScreenIdentifier?
        let presentation: Presentation?
        /// The containers' identifiers refused as a framework's, in tree order, each once.
        let refused: [String]
    }

    /// A presentation over the screen: the node that is it, and what it is — XCUITest's type, or `page sheet`.
    struct Presentation: Equatable {
        let scope: AXNode
        let kind: String

        /// How an answer names it: `the presented Alert`, `the presented page sheet`.
        var description: String {
            "the presented \(kind)"
        }
    }

    /// The type the runner's raw code stands for, in a bundle written before the runner named every type — `Type18` a popover, `Type19` the keyboard, `Type45` a search field, the three seen on real captures — and any other type as it is.
    static let typeAliases: [String: String] = ["Type18": "Popover", "Type19": "Keyboard", "Type45": "SearchField"]

    static func reading(_ tree: AXNode, fallingBackToUnstable: Bool) -> Reading {
        let presentation = presentation(in: tree)
        let scope = presentation.map { [$0.scope] } ?? screen(of: tree)
        let isPresented = presentation != nil
        var refused: [String] = []
        if let value = containerIdentifier(among: scope, refused: &refused) {
            return Reading(identifier: ScreenIdentifier(value: value, source: .content, isPresented: isPresented), presentation: presentation, refused: refused)
        }
        var unstable: ScreenIdentifier?
        // The title before the propagated identifier: a title is always the screen's own, where a shared identifier may be its rows'.
        if fallingBackToUnstable {
            if let value = navigationBarIdentifier(among: scope) {
                unstable = ScreenIdentifier(value: value, source: .navigationBar, isPresented: isPresented)
            } else if let value = propagatedIdentifier(among: scope) {
                unstable = ScreenIdentifier(value: value, source: .propagated, isPresented: isPresented)
            }
        }
        return Reading(identifier: unstable, presentation: presentation, refused: refused)
    }

    /// The topmost presentation over the screen — the last in tree order among the app's window and every later window but a keyboard's — or `nil` when nothing is presented.
    static func presentation(in tree: AXNode) -> Presentation? {
        let layers: [AXNode] = if let app = tree.children.firstIndex(where: isWindow) {
            [tree.children[app]] + tree.children[(app + 1)...].filter { !holdsKeyboard($0) }
        } else {
            tree.children
        }
        var found: [Presentation] = []
        presentations(among: layers, root: tree.frame, into: &found)
        return found.last
    }

    /// The type `type` is known by — itself, or what an old bundle's raw code stands for.
    static func canonicalType(_ type: String) -> String {
        typeAliases[type] ?? type
    }
}

private extension ScreenIdentifier {
    /// XCUITest's own types for a presentation, as ``canonicalType(_:)`` spells them.
    static let presentedTypes: Set<String> = ["Alert", "Sheet", "Popover"]

    /// The chrome an element-level child is never counted among: the three bars and the keyboard.
    static let chromeTypes: Set<String> = ScreenContentCheck.chromeTypes.union(["Keyboard"])

    /// The nodes the screen is read in when nothing is presented: the app's window — the first window in tree order — or, for a root holding no window, the root's children.
    static func screen(of tree: AXNode) -> [AXNode] {
        tree.children.first(where: isWindow).map { [$0] } ?? tree.children
    }

    /// Collects, in tree order, each presentation among `nodes` and inside their containers — never looking inside one found.
    static func presentations(among nodes: [AXNode], root: AXNode.Frame, into found: inout [Presentation]) {
        let sheets = pageSheets(among: nodes, root: root)
        for (index, node) in nodes.enumerated() {
            let type = canonicalType(node.type)
            if presentedTypes.contains(type) {
                found.append(Presentation(scope: node, kind: type))
            } else if sheets.contains(index) {
                found.append(Presentation(scope: node, kind: "page sheet"))
            } else if containerTypes.contains(type) {
                presentations(among: node.children, root: root, into: &found)
            }
        }
    }

    /// The positions among `nodes` of a page sheet's container: after a sibling reaching past the screen on every edge — the dimming view — and holding a button labelled `Sheet Grabber` among its own children.
    static func pageSheets(among nodes: [AXNode], root: AXNode.Frame) -> Set<Int> {
        guard let dimming = nodes.firstIndex(where: { overhangs($0.frame, root) }) else { return [] }
        return Set(nodes.indices.filter { $0 > dimming && nodes[$0].children.contains(where: isSheetGrabber) })
    }

    static func containerIdentifier(among nodes: [AXNode], refused: inout [String]) -> String? {
        for node in nodes where isContainer(node) {
            if let identifier = node.identifier, !identifier.isEmpty {
                guard isFrameworkIdentifier(identifier) else { return identifier }
                if !refused.contains(identifier) {
                    refused.append(identifier)
                }
            }
            if let found = containerIdentifier(among: node.children, refused: &refused) {
                return found
            }
        }
        return nil
    }

    static func navigationBarIdentifier(among nodes: [AXNode]) -> String? {
        for node in nodes {
            if node.type == "NavigationBar" {
                if let identifier = usable(node.identifier) {
                    return identifier
                }
            } else if isContainer(node), let found = navigationBarIdentifier(among: node.children) {
                return found
            }
        }
        return nil
    }

    static func propagatedIdentifier(among nodes: [AXNode]) -> String? {
        for node in nodes where isContainer(node) {
            if let identifier = propagatedIdentifier(of: node) ?? propagatedIdentifier(among: node.children) {
                return identifier
            }
        }
        return nil
    }

    /// The identifier carried by every element-level child of `node` — a child neither a container nor chrome — when there are at least two, not all images (a row of one symbol is the symbol's name), and no cells (an identifier on every row names the rows).
    static func propagatedIdentifier(of node: AXNode) -> String? {
        let elements = node.children.filter { !isContainer($0) && !chromeTypes.contains(canonicalType($0.type)) }
        guard elements.count >= 2,
              !elements.contains(where: { $0.type == "Cell" }),
              elements.contains(where: { $0.type != "Image" }),
              let identifier = elements.first?.identifier,
              elements.allSatisfy({ $0.identifier == identifier })
        else { return nil }
        return usable(identifier)
    }

    /// An identifier present, not blank, and not a framework's.
    static func usable(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty, !isFrameworkIdentifier(identifier) else { return nil }
        return identifier
    }

    /// Whether a framework set `identifier` rather than the app: a Swift-mangled class name, an underscore-private one, or one of ``frameworkIdentifiers``.
    static func isFrameworkIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("_Tt") || identifier.hasPrefix("_UI") || frameworkIdentifiers.contains(identifier)
    }

    static func isContainer(_ node: AXNode) -> Bool {
        containerTypes.contains(canonicalType(node.type))
    }

    static func isWindow(_ node: AXNode) -> Bool {
        node.type == "Window"
    }

    /// Whether `node` holds a keyboard, itself included — what makes a window the keyboard's.
    static func holdsKeyboard(_ node: AXNode) -> Bool {
        canonicalType(node.type) == "Keyboard" || node.children.contains(where: holdsKeyboard)
    }

    static func isSheetGrabber(_ node: AXNode) -> Bool {
        node.type == "Button" && node.label == "Sheet Grabber"
    }

    /// Whether `frame` reaches past `root` on every edge.
    static func overhangs(_ frame: AXNode.Frame, _ root: AXNode.Frame) -> Bool {
        frame.x < root.x && frame.y < root.y && frame.x + frame.width > root.x + root.width && frame.y + frame.height > root.y + root.height
    }
}
