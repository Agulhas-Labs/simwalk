//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle labels`: the claims it selects, and the refusal of one nobody wrote.
struct BundleLabelsCommandTests {
    /// A claim name nobody wrote is refused before anything is read, and the refusal lists the four that exist.
    @Test
    func anUnknownClaimIsRefusedListingTheClaims() {
        let message = BundleLabelsCommand.message(for: parseError(["x.simwalk", "--claim", "larger-text,bogus"]))

        #expect(message.contains("'bogus' is not an Accessibility Nutrition Label claim"))
        for claim in AccessibilityLabelClaim.allCases {
            #expect(message.contains(claim.rawValue))
        }
    }

    /// Naming claims reports those and no others, and a bundle with something missing exits as qualified.
    @Test
    func claimSelectsTheNamedClaimsAndAMissingItemIsQualified() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])
        let command = try BundleLabelsCommand.parse([bundle.url.path, "--claim", "larger-text, dark-interface"])

        let answer = try command.answer()

        #expect(answer.text.contains("[larger-text] incomplete"))
        #expect(answer.text.contains("[dark-interface] incomplete"))
        #expect(!answer.text.contains("[sufficient-contrast]"))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    private func parseError(_ arguments: [String]) -> Error {
        do {
            _ = try BundleLabelsCommand.parse(arguments)
            return ExitCode.success
        } catch {
            return error
        }
    }
}
