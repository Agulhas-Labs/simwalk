//
// Copyright © Agulhas Labs
//

import Foundation

/// Text drawn over text: two runs of one content section, or two content sections, whose frames cross beyond a tolerance on the run side.
///
/// A new overlap — one the reference does not have between the same runs by shape, or the same sections — is flagged plainly; one both sides have is flagged once, as also in the reference, since a collision both days share is still a collision.
///
/// **What is not an overlap, from two walks of one build** (2026-09-29):
/// - **bars** — a tab bar's items overlap each other by 9 pt as the system lays them out, and content scrolls under every bar, so bars are left out;
/// - **a control's tap target** — a 44 pt segmented control's frame reaches 2 pt into the paragraph below it at the default size, and 10 pt into the date above it at accessibility Large, where the frame is 59 pt tall around a pill the tree does not draw. So two runs overlap only when they cross by more than the tolerance across, and by more than half the shorter run's height down: glyphs over glyphs, which padding never reaches;
/// - **one element exposed twice** — the Settings sidebar carries its `Dictate` button twice, same text at the same frame (2026-10-20): one thing drawn once, not text over text. Different text at one frame is still an overlap, by the text as drawn rather than its shape: `12:05` over `13:45` share the shape `{n}:{n}`.
public struct OverlapRule: FormRule {
    /// The least crossing, in points, in each direction, that counts.
    public var tolerance: Double

    public init(tolerance: Double = BoxRule.defaultTolerance) {
        self.tolerance = tolerance
    }

    /// Overlapping runs, section by section in the run's order, then overlapping sections.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        let runFlags = run.contentSections.flatMap { runSection in
            let referenceSection = reference.section(keyed: runSection.key)
            let referencePairs = referenceSection.map { Set(runOverlaps(in: $0)) } ?? []
            return runOverlaps(in: runSection).map { pair in
                let alsoInReference = referencePairs.contains(pair)
                let referenceCrop = alsoInReference ? referenceSection.map { [reference.crop(of: $0, side: .reference)] } ?? [] : []
                return FormFlag(
                    key: runSection.key,
                    finding: .overlappingRuns(first: pair.first, second: pair.second, alsoInReference: alsoInReference),
                    crops: referenceCrop + [run.crop(of: runSection, side: .run)]
                )
            }
        }
        let referencePairs = Set(sectionOverlaps(in: reference).map { OverlapPair($0.0.key, $0.1.key) })
        let sectionFlags = sectionOverlaps(in: run).map { first, second in
            let alsoInReference = referencePairs.contains(OverlapPair(first.key, second.key))
            let referenceCrops = alsoInReference
                ? [first, second].compactMap { reference.section(keyed: $0.key) }.map { reference.crop(of: $0, side: .reference) }
                : []
            return FormFlag(
                key: first.key,
                finding: .overlappingSections(other: second.key, alsoInReference: alsoInReference),
                crops: referenceCrops + [run.crop(of: first, side: .run), run.crop(of: second, side: .run)]
            )
        }
        return runFlags + sectionFlags
    }

    /// The pairs of runs in `section` that cross, by shape, each once, in tree order; a run with another's text (``ScreenSection/TextRun/text``, not its shape) at the same frame is that one exposed twice.
    func runOverlaps(in section: ScreenSection) -> [OverlapPair] {
        var pairs: [OverlapPair] = []
        for (index, first) in section.textRuns.enumerated() {
            for second in section.textRuns.dropFirst(index + 1) where !isExposedTwice(first, second) && runsOverlap(first.frame, second.frame) {
                let pair = OverlapPair(first.shape, second.shape)
                if !pairs.contains(pair) {
                    pairs.append(pair)
                }
            }
        }
        return pairs
    }

    /// Whether two runs are one element the tree carries twice: the same text as drawn, at the same frame.
    func isExposedTwice(_ first: ScreenSection.TextRun, _ second: ScreenSection.TextRun) -> Bool {
        first.text == second.text && first.frame == second.frame
    }

    /// Whether two runs cross past the tolerance across and past half the shorter one's height down.
    func runsOverlap(_ first: AXNode.Frame, _ second: AXNode.Frame) -> Bool {
        first.horizontalOverlap(with: second) > tolerance
            && first.verticalOverlap(with: second) > max(tolerance, min(first.height, second.height) / 2)
    }

    /// The pairs of content sections in `capture` whose frames cross past the tolerance, in its order.
    func sectionOverlaps(in capture: SegmentedCapture) -> [(ScreenSection, ScreenSection)] {
        let content = capture.contentSections
        return content.enumerated().flatMap { index, first in
            content.dropFirst(index + 1).filter { first.frame.intersects($0.frame, tolerance: tolerance) }.map { (first, $0) }
        }
    }
}

extension OverlapRule {
    /// Two things that overlap, named the same way whichever is met first.
    struct OverlapPair: Hashable {
        let first: String
        let second: String

        init(_ one: String, _ other: String) {
            first = min(one, other)
            second = max(one, other)
        }
    }
}
