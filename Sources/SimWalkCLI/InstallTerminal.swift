//
// Copyright © Agulhas Labs
//

import Foundation

/// Who `simwalk install` asks whether to install into each agent found, and whether anyone is there to ask.
///
/// Injected so a test can stand in for the person at the terminal, or for their absence.
struct InstallTerminal: Sendable {
    /// Whether anyone is there to see the question and answer it — stdin and stdout are both terminals.
    let isInteractive: Bool

    /// Writes the question and reads one line of answer, `nil` at the end of input.
    let ask: @Sendable (String) -> String?

    /// The process's own terminal: the question to stdout without a newline, the answer from stdin.
    static let standard = InstallTerminal(
        isInteractive: isatty(FileHandle.standardInput.fileDescriptor) != 0 && isatty(FileHandle.standardOutput.fileDescriptor) != 0,
        ask: { question in
            try? FileHandle.standardOutput.write(contentsOf: Data(question.utf8))
            return readLine()
        }
    )
}
