//
// Copyright © Agulhas Labs
//

import Foundation

/// What a labelled container holds, judged one way for the reading-order audit and for the `bundle screen` listing: the test that says a node's label speaks for the text inside it (SimWalk#105), which `readingOrder` uses to count the node as one stop and the listing uses to fold its insides into one row (SimWalk#264).
struct LabelledStop {
    /// The element types that act on their own: one element whatever they contain, and a stop of their own inside a container.
    static let controls = AuditedControl.types.union(["SecureTextField", "SearchField"])

    /// Whether a labelled container is one VoiceOver stop that reads all the text inside it (SimWalk#105): its label carries every text leaf below, and nothing below is an enabled control.
    static func speaksForItsText(_ node: AXNode) -> Bool {
        guard !node.children.isEmpty, !AuditedControl.isBlank(node.label), let label = node.label else { return false }
        var leafTexts: [String] = []
        guard gatherLeafTexts(node.children, into: &leafTexts) else { return false }
        return !leafTexts.isEmpty && leafTexts.allSatisfy { label.contains($0) }
    }

    /// Collects the trimmed text of each text-carrying leaf below, or reports `false` at the first enabled control.
    static func gatherLeafTexts(_ nodes: [AXNode], into texts: inout [String]) -> Bool {
        for node in nodes {
            if controls.contains(node.type), node.isEnabled {
                return false
            }
            if node.children.isEmpty {
                let source = AuditedControl.isBlank(node.label) ? node.value : node.label
                if let source, !AuditedControl.isBlank(source) {
                    texts.append(source.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else if !gatherLeafTexts(node.children, into: &texts) {
                return false
            }
        }
        return true
    }

    /// The descendants of a labelled, non-control node that its row can fold (SimWalk#264), or nothing when it folds none.
    ///
    /// Every descendant that carries a label or value is an `Image` or text the node's label contains (the test ``speaksForItsText(_:)`` applies to leaves), and no enabled control is below. Only the leaves are returned, in tree order: a label- or value-carrying descendant with none of its own below it, and every `Image` wherever it sits. A container that carries a label and holds text or images is not a count of its own. A descendant with any other text makes the node list child by child.
    static func foldedInsides(of node: AXNode) -> [AXNode]? {
        guard !controls.contains(node.type), !node.children.isEmpty,
              !AuditedControl.isBlank(node.label), let label = node.label
        else { return nil }
        var insides: [AXNode] = []
        var carriesText = false
        guard gather(node.children, label: label, into: &insides, carriesText: &carriesText), !insides.isEmpty else { return nil }
        return insides
    }

    /// Appends the countable descendants of `nodes` to `insides`, or returns `false` at the first enabled control or text the label does not contain.
    ///
    /// `carriesText` reports whether any node in `nodes` carries a label or value.
    private static func gather(_ nodes: [AXNode], label: String, into insides: inout [AXNode], carriesText: inout Bool) -> Bool {
        for node in nodes {
            if controls.contains(node.type), node.isEnabled {
                return false
            }
            let source = AuditedControl.isBlank(node.label) ? node.value : node.label
            let carries = source.map { !AuditedControl.isBlank($0) } ?? false
            if let source, carries {
                guard node.type == "Image" || label.contains(source.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
                carriesText = true
            }
            var below = false
            let slot = insides.count
            if !gather(node.children, label: label, into: &insides, carriesText: &below) {
                return false
            }
            carriesText = carriesText || below
            if carries, node.type == "Image" || !below {
                insides.insert(node, at: slot)
            }
        }
        return true
    }
}
