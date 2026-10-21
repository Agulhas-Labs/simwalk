//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation

/// What a capture bundle holds, and fails to hold, for each App Store Accessibility Nutrition Label claim (SimWalk#163).
///
/// **A report, not a rule.** `bundle audit` judges what the captures contain; this reads the same records against what a claim needs and says what a person would still have to add. Each claim has four parts, each present only when it has something to say: the evidence the bundle holds, what fails, what is missing (each as the walkbook change that would supply it) and what SimWalk cannot check. **A claim is never held while anything is missing**, and a check that did not run (an audit that threw, a screenshot that would not decode) is missing, never a pass.
///
/// The rules behind the failures are the audit's own (`largeTypeOverflow`, `truncatedText`, Apple's `dynamicType` and `contrast`, the dark render ceiling), reused rather than restated.
public struct BundleLabels {
    private let bundle: CaptureBundle
    private let claims: [AccessibilityLabelClaim]
    private let recognizer: (any ScreenTextRecognizing)?

    /// - Parameters:
    ///   - claims: The claims to report; all four when empty. Ordered and de-duplicated by `AccessibilityLabelClaim.selection`.
    ///   - recognizer: Reads the text drawn in a screenshot, for `truncatedText`; without one Larger Text lists truncation as a manual check.
    public init(_ bundle: CaptureBundle, claims: [AccessibilityLabelClaim] = [], recognizer: (any ScreenTextRecognizing)? = nil) {
        self.bundle = bundle
        self.recognizer = recognizer
        self.claims = AccessibilityLabelClaim.selection(claims)
    }

    public func run() throws -> Report {
        let needsScan = claims.contains(.largerText) || claims.contains(.sufficientContrast)
        let scan = needsScan ? AppleAuditScan(bundle) : nil
        let captures = claims.contains(.largerText) ? try BundleAuditScope(bundle).captures() : []
        let reports = claims.map { claim -> ClaimReport in
            switch claim {
            case .largerText: largerText(scan: scan, captures: captures)
            case .darkInterface: darkInterface()
            case .sufficientContrast: sufficientContrast(scan: scan)
            case .differentiateWithoutColor: differentiateWithoutColor()
            }
        }
        return Report(claims: reports.map { $0.collapsingIdenticalFails() }, screenCount: bundle.manifest.screens.count)
    }
}

public extension BundleLabels {
    /// What every selected claim came to.
    struct Report: Sendable {
        public let claims: [ClaimReport]
        /// The screens the walk was asked for, the denominator of every "screens with" count.
        public let screenCount: Int
    }

    /// One claim's four parts.
    struct ClaimReport: Equatable, Sendable {
        public let claim: AccessibilityLabelClaim
        /// What the bundle holds for the claim.
        public var evidence: [String] = []
        /// What the bundle shows failing it.
        public var fails: [String] = []
        /// What the bundle lacks to say either way, each as the walkbook change to make.
        public var missing: [String] = []
        /// What SimWalk cannot check, which a person must.
        public var manual: [String] = []

        /// How many identical fail lines were folded into a `×N` line, so the lines shown stay fewer than the findings they stand for.
        public var foldedFindings = 0

        public var status: Status {
            if claim.isManualOnly {
                return .manualOnly
            }
            if !fails.isEmpty {
                return .fails
            }
            return missing.isEmpty ? .holds : .incomplete
        }

        /// Whether the bundle supports the claim: it checks something, finds nothing failing, and lacks nothing.
        public var holds: Bool {
            status == .holds
        }

        /// The failing findings, each counted, whether or not its line was folded into another's.
        public var findingCount: Int {
            fails.count + foldedFindings
        }

        /// Identical fail lines (two findings with no element on one screen and state print the same) become one line with `×N`.
        func collapsingIdenticalFails() -> ClaimReport {
            var counts: [String: Int] = [:]
            var order: [String] = []
            for line in fails {
                if counts[line] == nil {
                    order.append(line)
                }
                counts[line, default: 0] += 1
            }
            var folded = self
            folded.fails = order.map { counts[$0] == 1 ? $0 : "\($0) ×\(counts[$0] ?? 1)" }
            folded.foldedFindings = fails.count - order.count
            return folded
        }
    }
}

public extension BundleLabels.ClaimReport {
    /// How the bundle stands on the claim: failing wins over incomplete, since a failure is already an answer and a gap is not.
    enum Status: String, Sendable {
        case holds
        case fails
        case incomplete
        case manualOnly = "manual only"
    }
}

private extension BundleLabels {
    /// Apple's wording is text enlargeable to at least 200%, and Body is 17 pt at the default size: 40 pt at AX3 is 235% where AX2's 33 pt is 194%, so AX3 is the smallest size that reaches it.
    static var requiredTextSize: String {
        "UICTContentSizeCategoryAccessibilityXL"
    }

    static var textSizePrefix: String {
        "uictcontentsizecategoryaccessibility"
    }

    /// The accessibility sizes by their category suffix, as levels: AX1 is `M`, AX3 is `XL`, AX5 is `XXXL`.
    static let accessibilityLevels = ["m": 1, "l": 2, "xl": 3, "xxl": 4, "xxxl": 5]
    static let requiredLevel = 3

    struct ScreenCaptures {
        let id: String
        let captures: [CaptureManifest.StateCapture]
    }

    /// Every screen the walk asked for with the captures that are of it: a screen recorded as a different screen than the walkbook expected contributes none, as `bundle audit` does.
    var screens: [ScreenCaptures] {
        bundle.manifest.screens.map { screen in
            if case .unexpectedScreen = screen.outcome {
                return ScreenCaptures(id: screen.id, captures: [])
            }
            return ScreenCaptures(id: screen.id, captures: screen.captures)
        }
    }

    /// `<screen>: add a state with …`, said differently when the screen has no usable capture at all, where the route comes first.
    func addState(_ screen: ScreenCaptures, _ state: String, note: String = "") -> String {
        let lead = screen.captures.isEmpty ? "no usable capture here (fix its route first); then add" : "add"
        return "\(screen.id): \(lead) a state with \(state)\(note)"
    }

    func level(of capture: CaptureManifest.StateCapture) -> Int? {
        capture.state.dynamicTypeSize.flatMap { size in
            let lowered = size.lowercased()
            guard lowered.hasPrefix(Self.textSizePrefix) else { return nil }
            return Self.accessibilityLevels[String(lowered.dropFirst(Self.textSizePrefix.count))]
        }
    }

    func largerText(scan: AppleAuditScan?, captures: [BundleAuditScope.Capture]) -> ClaimReport {
        var report = ClaimReport(claim: .largerText)
        var unchecked: [String] = []
        var uncheckedAfterAudit: [String] = []
        let unreadablePaths = Set((scan?.unreadable ?? []).map(\.path))
        let failed = Set((scan?.failures ?? []).map { "\($0.screenID)\u{1F}\($0.stateSlug)" })
        for screen in screens {
            let reaching = screen.captures.filter { (level(of: $0) ?? 0) >= Self.requiredLevel }
            if reaching.isEmpty {
                let below = screen.captures.compactMap { capture in level(of: capture) == nil ? capture.state.dynamicTypeSize : capture.state.dynamicTypeSize.map { "\($0), below 200%" } }
                let note = below.isEmpty ? "" : " (captured at \(below.joined(separator: "; ")), not counted)"
                report.missing.append(addState(screen, "\"dynamicTypeSize\": \"\(Self.requiredTextSize)\"", note: note))
            } else {
                report.evidence.append("\(screen.id): \(reaching.compactMap(\.state.dynamicTypeSize).joined(separator: ", "))")
                let audited = reaching.filter { capture in
                    capture.appleAudit.map { !unreadablePaths.contains($0.path) } == true && !failed.contains("\(screen.id)\u{1F}\(capture.state.slug)")
                }
                if audited.isEmpty {
                    if reaching.contains(where: { $0.appleAudit == nil }) {
                        unchecked.append(screen.id)
                    } else {
                        uncheckedAfterAudit.append(screen.id)
                    }
                }
            }
        }
        // Recognition costs a Vision pass per capture, so it reads the accessibility-size captures, and the default-size ones only of a screen that has a finding there to compare against.
        let truncationRule = TruncatedTextAudit(recognizer: recognizer)
        let accessibilityCaptures = captures.filter { LargeTypeOverflowAudit.isAccessibilitySize($0.stateSlug) }
        var truncatedText = truncationRule.evaluate(accessibilityCaptures)
        let screensWithFindings = Set(truncatedText.findings.map(\.screenID))
        truncatedText.findings += truncationRule.evaluate(captures.filter { LargeTypeOverflowAudit.isDefaultSize($0.stateSlug) && screensWithFindings.contains($0.screenID) }).findings
        let overflow = LabelAuditSection(
            name: .largeTypeOverflow,
            noun: LargeTypeOverflowAudit.findingNoun,
            examinedNoun: LargeTypeOverflowAudit.examinedNoun,
            clause: LargeTypeOverflowAudit.findingClause,
            result: LargeTypeOverflowAudit().evaluate(captures),
            captureCount: captures.count
        )
        report.fails += overflow.distinct.map { row in
            "\(row.screenID): largeTypeOverflow — \(row.type)\(row.label.map { " '\(AuditRowFormat.trim($0))'" } ?? "")\(row.note.map { " \($0)" } ?? "") [\(row.states.joined(separator: ", "))]"
        }
        let truncation = LabelAuditSection(
            name: .truncatedText,
            noun: TruncatedTextAudit.findingNoun,
            examinedNoun: TruncatedTextAudit.examinedNoun,
            clause: TruncatedTextAudit.findingClause,
            result: truncatedText,
            captureCount: accessibilityCaptures.count
        )
        // Text that reads truncated at the default size too was not cut by the larger type: it is a manual line, not a fail.
        var byDesign: [(screen: String, labels: [String])] = []
        for row in truncation.distinct {
            let states = row.states.filter(LargeTypeOverflowAudit.isAccessibilitySize)
            guard !states.isEmpty else { continue }
            if row.states.contains(where: LargeTypeOverflowAudit.isDefaultSize) {
                let label = "'\(AuditRowFormat.trim(row.label ?? ""))'"
                if let index = byDesign.firstIndex(where: { $0.screen == row.screenID }) {
                    byDesign[index].labels.append(label)
                } else {
                    byDesign.append((row.screenID, [label]))
                }
                continue
            }
            report.fails.append("\(row.screenID): truncatedText —\(row.label.map { " '\(AuditRowFormat.trim($0))'" } ?? "")\(row.note.map { " \($0)" } ?? "") [\(states.joined(separator: ", "))]")
        }
        for entry in byDesign {
            report.manual.append("\(entry.screen): \(entry.labels.joined(separator: ", ")) \(entry.labels.count == 1 ? "reads" : "read") truncated at the default size too, so larger type did not cause it; check whether that is by design")
        }
        if let scan {
            for var row in AppleAuditSection(name: .appleDynamicType, scan: scan, listsUnreadable: false).distinct {
                row.states = row.states.filter(LargeTypeOverflowAudit.isAccessibilitySize)
                if !row.states.isEmpty {
                    report.fails.append("\(row.screenID): \(AuditRuleName.appleDynamicType.rawValue) — \(row.text) [\(row.states.joined(separator: ", "))]")
                }
            }
            let clipped = AppleAuditSection(name: .appleTextClipped, scan: scan, listsUnreadable: false).distinct.filter { row in
                row.states.contains(where: LargeTypeOverflowAudit.isAccessibilitySize)
            }
            if !clipped.isEmpty {
                var screenIDs: [String] = []
                for row in clipped where !screenIDs.contains(row.screenID) {
                    screenIDs.append(row.screenID)
                }
                report.manual.append("Apple's audit reports \(clipped.count) textClipped finding\(clipped.count == 1 ? "" : "s") at accessibility sizes on \(screenIDs.joined(separator: ", ")); its textClipped check proved unreliable, so check them by hand")
            }
        }
        report.manual.append("overlap between text elements that the accessibility tree does not show")
        if recognizer == nil {
            report.manual.append("whether text is drawn truncated: no text recognizer on this face, so truncatedText did not run")
        } else if truncatedText.unchecked > 0 {
            report.manual.append("whether text is drawn truncated on \(truncatedText.unchecked) capture\(truncatedText.unchecked == 1 ? "" : "s"): no readable screenshot")
        }
        if !unchecked.isEmpty {
            report.manual.append("Apple's Dynamic Type check on \(unchecked.joined(separator: ", ")): its audit did not check the large-type capture (walk with --apple-audit)")
        }
        if !uncheckedAfterAudit.isEmpty {
            report.manual.append("Apple's Dynamic Type check on \(uncheckedAfterAudit.joined(separator: ", ")): its audit of the large-type capture failed or could not be read (walk again)")
        }
        return report
    }

    func darkInterface() -> ClaimReport {
        var report = ClaimReport(claim: .darkInterface)
        for screen in screens {
            let dark = screen.captures.filter { $0.state.theme == .dark }
            if dark.isEmpty {
                report.missing.append(addState(screen, "\"theme\": \"dark\""))
            }
            for capture in dark {
                let name = "\(screen.id) [\(capture.state.slug)]"
                let brightness = (try? Data(contentsOf: bundle.screenshotURL(for: capture))).flatMap { ScreenshotBrightness.mean(ofPNG: $0) }
                guard let brightness else {
                    report.missing.append("\(name): not measured, the screenshot would not decode (walk again)")
                    continue
                }
                let figure = String(format: "%.2f", brightness)
                if brightness > StateApplicationCheck.darkRenderCeiling {
                    report.fails.append("\(name): mean brightness \(figure) is above the dark ceiling \(String(format: "%.2f", StateApplicationCheck.darkRenderCeiling)), so it drew light")
                } else {
                    report.evidence.append("\(name): mean brightness \(figure)")
                }
            }
        }
        return report
    }

    func sufficientContrast(scan: AppleAuditScan?) -> ClaimReport {
        var report = ClaimReport(claim: .sufficientContrast)
        guard let scan else { return report }
        let failures = Dictionary(scan.failures.map { ("\($0.screenID)\u{1F}\($0.stateSlug)", $0.reason) }, uniquingKeysWith: { first, _ in first })
        let unreadable = Dictionary(scan.unreadable.map { ($0.path, $0.reason) }, uniquingKeysWith: { first, _ in first })
        for screen in screens {
            for theme in [Walkbook.Theme.light, .dark] {
                let captures = screen.captures.filter { $0.state.theme == theme }
                var audited = 0
                for capture in captures {
                    let name = "\(screen.id) [\(capture.state.slug)]"
                    if let reason = failures["\(screen.id)\u{1F}\(capture.state.slug)"] {
                        report.missing.append("\(name): Apple's audit failed (\(reason)), not checked; walk again")
                    } else if let entry = capture.appleAudit, let reason = unreadable[entry.path] {
                        report.missing.append("\(name): the audit record is unreadable (\(reason)), not checked; walk again")
                    } else if capture.appleAudit != nil {
                        audited += 1
                    }
                }
                if audited > 0 {
                    report.evidence.append("\(screen.id): \(theme.rawValue) audited in \(audited) of \(captures.count) capture\(captures.count == 1 ? "" : "s")")
                } else if captures.isEmpty {
                    report.missing.append(addState(screen, "\"theme\": \"\(theme.rawValue)\"", note: " and walk with --apple-audit"))
                } else if !captures.contains(where: { $0.appleAudit != nil }) {
                    report.missing.append("\(screen.id): \(theme.rawValue) was not audited; walk with --apple-audit")
                }
            }
        }
        report.fails += AppleAuditSection(name: .appleContrast, scan: scan, listsUnreadable: false).distinct.map { "\($0.screenID): appleContrast — \($0.text) [\($0.states.joined(separator: ", "))]" }
        if let made = bundle.manifest.deviceSetup?.made.first(where: { $0.hasPrefix(CaptureManifest.SetupRecord.increaseContrastPrefix) }) {
            report.evidence.append("every audit in this bundle was taken with Increase Contrast on: \(made)")
            report.missing.append("the default appearance was not audited: walk again without \"increaseContrast\" and run labels on that bundle too")
        } else {
            // Apple's criteria ask for the ratios by default and suggest testing with Increase Contrast on as well, so a default bundle can hold the claim and the second walk is a check, not a gap.
            report.manual.append("Increase Contrast: Apple also suggests testing with it on; walk again with \"setup\": {\"increaseContrast\": true} and run labels on that bundle")
        }
        report.manual.append("Bold Text and Reduce Transparency: a walk cannot set either, and `simctl ui` has no option for them")
        return report
    }

    func differentiateWithoutColor() -> ClaimReport {
        var report = ClaimReport(claim: .differentiateWithoutColor)
        report.manual.append("a simulator cannot be put in Grayscale from the host (`simctl ui` offers appearance, increase_contrast and content_size only), so check each screen by hand with a Grayscale colour filter on a device")
        return report
    }
}
