//
// Copyright © Agulhas Labs
//

import Foundation

/// A ``BundleDiff`` as text: the two builds and what a flag can mean, the tallies, then one line per flag under the state it is on.
///
/// **Compact enough for a screen's budget of about fifty lines.** A state with no flag is not listed — the tally counts it — and a screen whose every state is clean is named once, on one line, so the reader can see it was compared. What is unpaired or not compared is always listed: an omission would read as "no difference".
public struct BundleDiffRendering {
    /// The diff as lines of text.
    ///
    /// With `crops`, each flag's crop carries the bare name of the file it was written to, and the header names the directory once.
    public static func lines(of diff: BundleDiff, crops: BundleDiffCrops? = nil) -> [String] {
        header(diff, crops: crops) + diff.screens.flatMap { screenLines($0, crops: crops) } + cleanLine(diff)
    }

    /// The diff as one block of text.
    public static func render(_ diff: BundleDiff) -> String {
        lines(of: diff).joined(separator: "\n")
    }

    /// The two builds and what is known of them, the tallies, and the screens on one side only.
    static func header(_ diff: BundleDiff, crops: BundleDiffCrops? = nil) -> [String] {
        identityLines(diff) + cropsLines(crops) + ["\(count(diff.flagCount, "flag")) · \(comparedTally(diff))" + inheritedClause(diff)] + unpairedLines(diff)
    }

    /// The two builds, and whether the build and the walkbook are the same: facts only, since what a flag is evidence of is the reader's to judge.
    static func identityLines(_ diff: BundleDiff) -> [String] {
        [
            "bundle diff: run \(diff.run.walkName) build \(AppBuildIdentity.printed(diff.run.appBuildHash)) against reference \(diff.reference.walkName) build \(AppBuildIdentity.printed(diff.reference.appBuildHash))",
            factsLine(diff),
        ]
    }

    /// Whether the two bundles are of the same build and the same walkbook.
    static func factsLine(_ diff: BundleDiff) -> String {
        let unread = [diff.reference, diff.run].contains { $0.appBuildHash == AppBuildIdentity.unreadOnDevice }
        let installed = [diff.reference, diff.run].contains { $0.appBuildProvenance == .installed }
        let same = installed ? "same (installed, not read back)" : "same"
        let build = unread ? "unread" : diff.reference.isSameBuild(as: diff.run) ? same : "different"
        let walkbook = diff.reference.walkbookHash == diff.run.walkbookHash ? "same" : "changed \(ShortHash.of(diff.reference.walkbookHash)) → \(ShortHash.of(diff.run.walkbookHash))"
        return "build \(build) · walkbook \(walkbook)"
    }

    /// The directory the crops went into, said once so the flag lines can name files bare; nothing when no crops were asked for.
    static func cropsLines(_ crops: BundleDiffCrops?) -> [String] {
        guard let crops, !crops.directory.isEmpty else { return [] }
        return ["crops in \(crops.directory)"]
    }

    /// The screens and states that were compared.
    static func comparedTally(_ diff: BundleDiff) -> String {
        let compared = diff.screens.filter(\.isCompared)
        let states = compared.reduce(0) { $0 + $1.states.filter(\.isCompared).count }
        return "\(count(compared.count, "screen")) compared, \(count(states, "state"))"
    }

    /// The flags both bundles carry, said apart from the differences: `, 2 flags also in the reference (not counted)`, or nothing when there are none.
    static func inheritedClause(_ diff: BundleDiff) -> String {
        diff.inheritedFlagCount > 0 ? ", \(count(diff.inheritedFlagCount, "flag")) also in the reference (not counted)" : ""
    }

    /// The screens on one side only, a line per side.
    static func unpairedLines(_ diff: BundleDiff) -> [String] {
        [BundleDiff.Side.reference, .run].compactMap { side in
            let ids = diff.unpairedScreens.filter { $0.side == side }.map(\.id)
            return ids.isEmpty ? nil : "\(side.rawValue) only: \(ids.joined(separator: ", "))"
        }
    }

    /// One screen's lines: why it was not compared, the states on one side only, and each flagged or unreadable state with its flags.
    static func screenLines(_ screen: ScreenDiff, crops: BundleDiffCrops? = nil) -> [String] {
        guard screen.isCompared else {
            let reference = CaptureBundleSummary.outcomeWords(screen.referenceOutcome)
            let run = CaptureBundleSummary.outcomeWords(screen.runOutcome)
            return ["\(screen.id): not compared — reference \(reference), run \(run)"]
        }
        let unpaired = screen.unpairedStates.map { "\(screen.id)/\($0.slug): \($0.side.rawValue) only — \($0.screenshotPath)" }
        return unpaired + stateLines(of: screen, crops: crops) + shiftLines(of: screen)
    }

    /// One line per layout shift on one side only, then a note for each state whose shifts could not be compared; a shift flag has no crop, so `bundle screen --match` is how to find its element.
    static func shiftLines(of screen: ScreenDiff) -> [String] {
        let flags = (screen.shiftFlags ?? []).map { flag in
            "  shift only in \(flag.side.rawValue) \(screen.id)/\(flag.slug): \(elementText(flag.shift.element)) moved \(moveText(flag.shift)) pt — cause: \(causeText(flag.shift.cause))"
        }
        let notes = (screen.shiftNotes ?? []).map { "  \(screen.id)/\($0.slug): motion not compared: no shift record on \($0.missingSide.rawValue)" }
        return flags + notes
    }

    /// `Button 'Row 2'`: the type and the name a reader would look it up by; `Cell in 'Groceries'` for an anonymous element, which has only the name of what holds it.
    static func elementText(_ element: CaptureManifest.Motion.Element) -> String {
        if let name = element.label ?? element.identifier {
            return "\(element.type) '\(name)'"
        }
        return element.within.map { "\(element.type) in '\($0)'" } ?? element.type
    }

    /// `0,+72`: how far the box's origin moved, signed.
    static func moveText(_ shift: CaptureManifest.Motion.Shift) -> String {
        func signed(_ value: Double) -> String {
            let rounded = Int(value.rounded())
            return rounded > 0 ? "+\(rounded)" : "\(rounded)"
        }
        return "\(signed(shift.after.x - shift.before.x)),\(signed(shift.after.y - shift.before.y))"
    }

    static func causeText(_ cause: CaptureManifest.Motion.Cause?) -> String {
        cause.map { "\($0.change.rawValue) \(elementText($0.element))" } ?? "no cause named"
    }

    private static func stateLines(of screen: ScreenDiff, crops: BundleDiffCrops?) -> [String] {
        screen.states.flatMap { state -> [String] in
            let path = "\(screen.id)/\(state.slug)"
            for (side, segmentation) in [(BundleDiff.Side.reference, state.reference), (.run, state.run)] {
                if let reason = segmentation.unreadable {
                    return ["\(path): not compared — the \(side.rawValue)'s tree could not be read: \(reason)"]
                }
            }
            guard !state.flags.isEmpty else { return [] }
            let screenshot = state.run.screenshotPath
            return ["\(path): \(count(state.flags.count, "flag")) · \(screenshot)"] + state.flags.enumerated().map { index, flag in
                "  " + flagLine(flag, screenshot: screenshot) { crop, side in crops?.outcomes[BundleDiffCrops.Key(screen: screen.id, state: state.slug, flag: index + 1, crop: crop, side: side)] }
            }
        }
    }

    /// The screens compared with every state clean, named once.
    static func cleanLine(_ diff: BundleDiff) -> [String] {
        let clean = diff.screens.filter { screen in
            screen.isCompared && screen.unpairedStates.isEmpty && (screen.shiftFlags ?? []).isEmpty && (screen.shiftNotes ?? []).isEmpty && screen.states.allSatisfy { $0.isCompared && $0.flags.isEmpty }
        }
        return clean.isEmpty ? [] : ["no form difference: \(clean.map(\.id).joined(separator: ", "))"]
    }

    /// One flag: the rule, the section, what differs, and its crops — each crop's screenshot path left out where it is `screenshot`, which the state's line has already said.
    ///
    /// `outcome` says what became of each crop (by its 1-based position in the flag, and its side) when crops were written: the file's bare name, or why there is none.
    static func flagLine(_ flag: FormFlag, screenshot: String, outcome: (_ crop: Int, _ side: BundleDiff.Side) -> BundleDiffCrops.Outcome? = { _, _ in nil }) -> String {
        let finding = switch flag.finding {
        case let .onlyIn(side):
            "\(side.rawValue) only"
        case let .onlyInList(side):
            "\(side.rawValue) only · list — may be data-driven"
        case let .moved(referencePosition, runPosition, shared):
            "\(referencePosition) → \(runPosition) of \(shared) shared"
        case let .box(changes):
            changes.map { "\(measureName($0.measure)) \(points($0.reference)) → \(points($0.run))" }.joined(separator: ", ")
        case let .rowTemplate(side, template, row):
            "\(side.rawValue) only: \(row.joined(separator: " | ")) (\(template.map(\.rawValue).joined(separator: ", ")))"
        case let .overlappingRuns(first, second, alsoInReference):
            "\"\(first)\" over \"\(second)\"" + alsoTag(alsoInReference)
        case let .overlappingSections(other, alsoInReference):
            "over \(other)" + alsoTag(alsoInReference)
        case let .degenerateChart(axis, plot, alsoInReference):
            "axis \(axis.joined(separator: " … ")) under a \(points(plot)) pt plot" + alsoTag(alsoInReference)
        }
        let crops = flag.crops.enumerated().map { index, crop in
            let path = crop.screenshotPath == screenshot ? "" : " " + crop.screenshotPath
            return "\(sideTag(crop.side))\(path) \(rectText(crop))\(cropText(outcome(index + 1, crop.side)))"
        }
        return "\(flag.rule)  \(flag.key)  \(finding) · \(crops.joined(separator: " · "))"
    }

    /// Where a crop went, or why it did not: nothing for a crop whose absence `rectText` already states.
    static func cropText(_ outcome: BundleDiffCrops.Outcome?) -> String {
        switch outcome {
        case let .written(path): " → \(URL(fileURLWithPath: path).lastPathComponent)"
        case let .failed(reason): " (crop not written: \(reason))"
        case .notInScreenshot, nil: ""
        }
    }

    /// What a flag raised on the run side adds when the reference has the same finding.
    static func alsoTag(_ alsoInReference: Bool) -> String {
        alsoInReference ? ", also in reference" : ""
    }

    static func sideTag(_ side: BundleDiff.Side) -> String {
        switch side {
        case .reference: "ref"
        case .run: "run"
        }
    }

    /// A crop's rect as `x,y w×h` in points, with how much of the section it shows when not all of it.
    static func rectText(_ crop: SectionCrop) -> String {
        let rect = "@\(points(crop.rect.x)),\(points(crop.rect.y)) \(points(crop.rect.width))×\(points(crop.rect.height))"
        return switch crop.visibility {
        case .whole: rect
        case .clipped: rect + " clipped"
        case .notInScreenshot: rect + " not in screenshot"
        }
    }

    static func measureName(_ measure: FormFlag.BoxMeasure) -> String {
        switch measure {
        case .leadingEdge: "leading edge"
        case .top: "top"
        case .gapAbove: "gap above"
        case .width: "width"
        case .height: "height"
        }
    }

    /// A length in whole points: the tolerance is several points, so a fraction adds digits and no information.
    static func points(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
