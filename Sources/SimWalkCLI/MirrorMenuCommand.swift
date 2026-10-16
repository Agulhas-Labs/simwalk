//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror menu home|switcher` — a click on iPhone Mirroring's View menu, the only navigation that never types.
struct MirrorMenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "menu", abstract: "Click a View menu item of iPhone Mirroring: home (Home Screen) or switcher (App Switcher).")

    @Argument(help: "home or switcher.")
    var item: String

    @OptionGroup var options: MirrorStepOptions

    func run() throws {
        try TimedCall.run(tool: "mirror menu", target: item, defaultFailureKind: .toolError) {
            try perform()
        }
    }

    /// What follows the App Switcher, since `Home Screen` from there lands in the last app first.
    static var switcherResidue: String {
        "next: 'menu home' from the App Switcher lands in the last app first — send it twice"
    }

    func perform(makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper, timeZone: TimeZone = .current) throws -> Answer {
        guard let menuItem = MirrorMenuItem.allCases.first(where: { $0.spelling == item }) else {
            throw InputRefusal("'\(item)' is not a menu item — it is one of \(MirrorMenuItem.allCases.map(\.spelling).joined(separator: ", "))")
        }
        let answer = try options.answer(.menu(menuItem), makeStepper: makeStepper, timeZone: timeZone)
        guard menuItem == .appSwitcher else { return answer }
        return Answer(header: answer.header, verdict: answer.verdict, residue: answer.residue + [Self.switcherResidue], weighing: answer.weighing)
    }
}
