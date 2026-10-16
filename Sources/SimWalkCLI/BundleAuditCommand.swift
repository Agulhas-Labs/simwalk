//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk bundle audit <path>` — checks one bundle against itself, without a reference frame or a second run.
struct BundleAuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Check a bundle against itself: disclosure rows not typed as controls, and controls with no label, a symbol name for a label, or a label another control shares. Every rule runs unless --only names some."
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    @Option(name: .long, help: ArgumentHelp("Run only this rule; repeat to run several. Rules: \(BundleAuditCommand.ruleNames).", valueName: "rule"))
    var only: [String] = []

    /// A walkbook whose screens' `budgets` the motionBudget and performanceBudget rules hold the bundle's recorded motion and device performance to.
    @Option(name: .long, help: ArgumentHelp("A walkbook whose screens' `budgets` the motionBudget rule (settleMs, layoutShifts) and the performanceBudget rule (launchMs, transitionHitches, cpuMs, memoryPeakMB) hold the bundle's recorded motion and device performance to. Without budgets for a rule it prints `not run` in a full run, and `--only` naming it is refused.", valueName: "walkbook.json"))
    var walkbook: String?

    /// A rule name nobody wrote is refused before anything is read, naming the ones that exist — a typo must not become a silent run of a different rule set, or of none.
    func validate() throws {
        if let unknown = only.first(where: { AuditRuleName(rawValue: $0) == nil }) {
            throw ValidationError("'\(unknown)' is not a bundle audit rule — the rules are \(Self.ruleNames)")
        }
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its three effects injectable, for the reason `TimedCall` takes them: the contract this command holds is an exit code, and an exit code is only checkable against the command itself.
    ///
    /// The code is no longer computed here. An audit that found something, and one over a bundle whose screens were never opened, are both *qualified answers* — the verdict says so on the second line, and `TimedCall` exits on what the verdict says, so the report and the code cannot disagree.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        try run(log: log, emit: emit, emitError: emitError, isStdoutPiped: isStdoutPiped) { try answer() }
    }

    /// The same run with the answer itself injectable too, so the kind an unmapped failure records can be checked without a bundle that could produce one.
    ///
    /// Every failure of the bundle argument is a `CaptureBundleError`, classified on its own account — a tree the runner wrote that does not decode is `runner-failed` there, not here. What is left is this command's own code over a bundle it has already read, so an unmapped failure is `tool-error`, never a caller's mistake.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "bundle audit", target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, body: body)
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    func answer() throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        let rules = only.compactMap(AuditRuleName.init(rawValue:))
        let book = try walkbook.map { try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: $0)) }
        let budgets = Dictionary(uniqueKeysWithValues: (book?.screens ?? []).compactMap { screen in screen.budgets.map { (screen.id, $0) } })
        let motionBudgets = budgets.filter(\.value.hasMotionBudget)
        let performanceBudgets = budgets.filter(\.value.hasPerformanceBudget)
        // Asked for by name over nothing to check, an `ok` over 0 rules would read as a pass: a refused call, like any argument that cannot be honoured.
        if motionBudgets.isEmpty, only.contains(AuditRuleName.motionBudget.rawValue) {
            let why = book == nil ? "pass --walkbook with a walkbook whose screens state \"budgets\"" : budgets.isEmpty ? "the walkbook passed states no \"budgets\"" : "the walkbook passed states no motion \"budgets\" (settleMs, layoutShifts)"
            throw InputRefusal("motionBudget has no budgets to check: \(why)")
        }
        if performanceBudgets.isEmpty, only.contains(AuditRuleName.performanceBudget.rawValue) {
            let why = book == nil ? "pass --walkbook with a walkbook whose screens state \"budgets\" with launchMs, transitionHitches, cpuMs or memoryPeakMB" : "the walkbook passed states no performance \"budgets\" (launchMs, transitionHitches, cpuMs, memoryPeakMB)"
            throw InputRefusal("performanceBudget has no budgets to check: \(why)")
        }
        let report = try BundleAudit(opened, rules: rules, budgets: budgets).run()
        // As `bundle oracle` does: budgets are tightened after a walk, so a walkbook that is not the one the bundle was walked from qualifies rather than refuses.
        let changed = try book.map { try !WalkbookIdentity.isPlan($0, of: opened.manifest) } ?? false
        let ran = (!motionBudgets.isEmpty && (only.isEmpty || only.contains(AuditRuleName.motionBudget.rawValue)))
            || (!performanceBudgets.isEmpty && (only.isEmpty || only.contains(AuditRuleName.performanceBudget.rawValue)))
        let qualified = changed && ran ? ["walkbook changed since the walk; budgets matched by screen id"] : []
        return BundleAuditSummary(report, of: opened, qualifiedBy: qualified, walkbookPassed: book != nil, budgetsStated: !budgets.isEmpty).answer()
    }

    private static var ruleNames: String {
        AuditRuleName.allCases.map(\.rawValue).joined(separator: ", ")
    }
}
