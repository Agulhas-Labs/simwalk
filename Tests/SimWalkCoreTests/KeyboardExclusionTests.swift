//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The keyboard a `type` step leaves up is input laid over the screen, not the screen being judged: the capture keeps it, and no judgement of the app's layout or labels reads it (SimWalk#215).
struct KeyboardExclusionTests {
    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AXNode.Frame {
        AXNode.Frame(x: x, y: y, width: width, height: height)
    }

    /// The keyboard as the runner records it: its own window, a suggestion bar of words and a row of keys, an `Emoji` key over the tab bar.
    private static func keyboard(suggestions: [String] = ["Is", "And", "Said"], extra: [AXNode] = []) -> AXNode {
        let bar = AXNode(type: "Other", frame: frame(0, 560, 402, 44), children: suggestions.enumerated().map { index, word in
            AXNode(type: "Button", frame: frame(Double(index) * 134, 560, 134, 44), label: word, children: [
                AXNode(type: "StaticText", frame: frame(Double(index) * 134 + 40, 570, 50, 20), label: word),
            ])
        })
        let keys = AXNode(type: "Other", frame: frame(0, 604, 402, 270), children: [
            AXNode(type: "Key", frame: frame(0, 604, 40, 50), label: "q"),
            AXNode(type: "Key", frame: frame(40, 604, 40, 50), label: "w"),
            AXNode(type: "Button", frame: frame(0, 800, 40, 74), label: "Emoji"),
        ] + extra)
        return AXNode(type: "Window", frame: frame(0, 0, 402, 874), children: [
            AXNode(type: "Keyboard", frame: frame(0, 560, 402, 314), children: [bar, keys]),
        ])
    }

    /// An app window of two labelled lines and a tab bar, with the keyboard's window beside it.
    private static func tree(suggestions: [String] = ["Is", "And", "Said"]) -> AXNode {
        let content = AXNode(type: "CollectionView", frame: frame(0, 100, 402, 600), children: [
            AXNode(type: "StaticText", frame: frame(16, 560, 300, 20), label: "Nickname is Robin"),
            AXNode(type: "StaticText", frame: frame(16, 600, 300, 20), label: "Said"),
        ])
        let tabBar = AXNode(type: "TabBar", frame: frame(0, 780, 402, 94), children: [
            AXNode(type: "Button", frame: frame(0, 780, 100, 49), label: "Hub"),
        ])
        return AXNode(type: "Application", frame: frame(0, 0, 402, 874), label: "Fixture", children: [
            AXNode(type: "Window", frame: frame(0, 0, 402, 874), children: [content, tabBar]),
            keyboard(suggestions: suggestions),
        ])
    }

    private static func segmented(_ tree: AXNode) -> SegmentedCapture {
        SegmentedCapture(tree: tree, screenshotPath: "screens/form/light/screen.png", segmenter: AXSegmenter())
    }

    @Test
    func noSectionOrRunCarriesAKeyOrASuggestion() {
        let sections = AXSegmenter().sections(of: Self.tree())
        let texts = sections.flatMap(\.textRuns).map(\.text)

        #expect(texts.contains("Nickname is Robin"))
        for word in ["Is", "And", "Emoji", "q"] {
            #expect(!texts.contains(word))
        }
        #expect(sections.map(\.key).allSatisfy { !["Is", "And", "Emoji", "q"].contains($0) })
    }

    @Test
    func theKeyboardOverTheAppAndItsTabBarIsNoOverlap() {
        let capture = Self.segmented(Self.tree())

        #expect(OverlapRule().flags(reference: capture, run: capture).isEmpty)
    }

    @Test
    func twoCapturesDifferingOnlyInSuggestionWordsRaiseNoFlag() {
        let reference = Self.segmented(Self.tree(suggestions: ["Is", "And", "Said"]))
        let run = Self.segmented(Self.tree(suggestions: ["The", "I", "Robin"]))

        for rule in BundleDiff.standardRules {
            #expect(rule.flags(reference: reference, run: run).isEmpty, "\(type(of: rule))")
        }
    }

    @Test
    func aKeyboardOldBundlesRecordedAsATypeCodeIsLeftOutToo() {
        var tree = Self.tree()
        tree.children[1].children[0].type = "Type19"

        #expect(!AXSegmenter().sections(of: tree).flatMap(\.textRuns).map(\.text).contains("Is"))
    }

    // MARK: Audit rules that walk the tree themselves

    @Test
    func smallTargetDoesNotJudgeTheKeyboardsButtons() {
        let small = AXNode(type: "Button", frame: Self.frame(20, 100, 30, 30), label: "Close")
        var tree = Self.tree()
        tree.children.insert(small, at: 0)

        let result = SmallTargetAudit().evaluate(tree, screenID: "form", stateSlug: "light")

        #expect(result.findings.map(\.label) == ["Close"])
    }

    @Test
    func largeTypeOverflowDoesNotJudgeTheSuggestionWords() {
        func pair(_ first: String, _ second: String, y: Double) -> AXNode {
            AXNode(type: "Other", frame: Self.frame(0, y - 10, 402, 60), children: [
                AXNode(type: "StaticText", frame: Self.frame(20, y, 100, 20), label: first),
                AXNode(type: "StaticText", frame: Self.frame(60, y, 100, 20), label: second),
            ])
        }
        let tree = LabelTreeFixture.screen([
            pair("Save", "Done", y: 100),
            AXNode(type: "Keyboard", frame: Self.frame(0, 560, 402, 314), children: [pair("Is", "And", y: 600)]),
        ])

        let result = LargeTypeOverflowAudit().evaluate(tree, screenID: "form", stateSlug: "dark-dt_uictcontentsizecategoryaccessibilityl")

        #expect(result.findings.map(\.label) == ["Save"])
        #expect(result.examined == 2)
    }

    @Test
    func truncatedTextDoesNotJudgeTheKeyboard() {
        let title = AXNode(type: "StaticText", frame: Self.frame(20, 100, 150, 20), label: "Notifications")
        let cut = AXNode(type: "StaticText", frame: Self.frame(20, 300, 150, 20), label: "Notifications")
        let screen = AXNode(type: "Application", frame: Self.frame(0, 0, 400, 800), children: [
            title,
            AXNode(type: "Keyboard", frame: Self.frame(0, 280, 400, 300), children: [cut]),
        ])
        let lines = [
            MirrorTextLine(text: "Notific…", centreX: 0.2, centreY: 0.125, width: 0.2, height: 0.02, confidence: 1),
            MirrorTextLine(text: "Notific…", centreX: 0.2, centreY: 0.3875, width: 0.2, height: 0.02, confidence: 1),
        ]

        let result = TruncatedTextAudit(recognizer: nil).evaluate(screen, lines: lines, screenID: "form", stateSlug: "dark-dt_uictcontentsizecategoryaccessibilityxl")

        #expect(result.findings.map(\.frame.y) == [100])
        #expect(result.examined == 1)
    }

    @Test
    func disclosureAffordanceDoesNotReadAKeyboardKeyAsARow() {
        func row(_ y: Double) -> AXNode {
            AXNode(type: "Button", frame: Self.frame(16, y, 370, 44), label: "Row", children: [
                AXNode(type: "Image", frame: Self.frame(370, y + 15, 8, 14)),
            ])
        }
        let tree = AXNode(type: "Application", frame: Self.frame(0, 0, 402, 874), children: [
            row(100),
            AXNode(type: "Keyboard", frame: Self.frame(0, 560, 402, 314), children: [row(600)]),
        ])

        let rows = DisclosureAffordanceAudit.disclosureRows(in: tree, screenID: "form", stateSlug: "light")

        #expect(rows.map(\.frame.y) == [100])
    }

    @Test
    func unlabelledControlDoesNotJudgeTheKeyboard() {
        let tree = LabelTreeFixture.screen([
            LabelTreeFixture.element("Button", y: 0),
            AXNode(type: "Keyboard", frame: Self.frame(0, 560, 402, 314), children: [LabelTreeFixture.element("Button", y: 600)]),
        ])

        let result = UnlabelledControlAudit().evaluate(tree, screenID: "form", stateSlug: "light")

        #expect(result.findings.map(\.frame.y) == [0])
        #expect(result.examined == 1)
    }

    @Test
    func symbolNameLabelDoesNotJudgeTheKeyboard() {
        let tree = LabelTreeFixture.screen([
            LabelTreeFixture.element("Button", label: "xmark", y: 0),
            AXNode(type: "Keyboard", frame: Self.frame(0, 560, 402, 314), children: [LabelTreeFixture.element("Button", label: "chevron.right", y: 600)]),
        ])

        let result = SymbolNameLabelAudit().evaluate(tree, screenID: "form", stateSlug: "light")

        #expect(result.findings.map(\.label) == ["xmark"])
    }

    @Test
    func duplicateLabelDoesNotPairTheKeyboardsButtonsWithTheApps() {
        let tree = LabelTreeFixture.screen([
            LabelTreeFixture.element("Button", label: "Is", y: 0),
            AXNode(type: "Keyboard", frame: Self.frame(0, 560, 402, 314), children: [LabelTreeFixture.element("Button", label: "Is", y: 600)]),
        ])

        let result = DuplicateLabelAudit().evaluate(tree, screenID: "form", stateSlug: "light")

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func readingOrderLeavesOutAKeyboardOldBundlesRecordedAsATypeCode() {
        let tree = LabelTreeFixture.screen([
            LabelTreeFixture.element("Button", label: "Save", y: 0),
            AXNode(type: "Type19", frame: Self.frame(0, 560, 402, 314), children: [
                LabelTreeFixture.element("Button", label: "Is", y: 600),
                LabelTreeFixture.element("Button", label: "And", y: 650),
            ]),
        ])

        let result = ReadingOrderAudit().evaluate(tree, screenID: "form", stateSlug: "light")

        #expect(result.examined == 1)
    }
}
