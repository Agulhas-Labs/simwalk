//
// Copyright © Agulhas Labs
//

import Foundation

/// The one word a caller acts on, on the second line of every answer, and the exit code it maps to.
///
/// **The word and the code are one value, not two that agree.** A verdict rendered by the summary and an exit code decided by the command were two statements of the same judgement, and the only thing keeping them in step was that someone had written both — which is exactly how `bundle inspect` came to print a bundle's qualifications and exit 0 over them. Here the code is derived from the word, so a face cannot say "qualified" and exit as though nothing were.
public enum AnswerVerdict: Equatable, Sendable {
    /// The answer is complete and carries no qualification; the detail is what it is an answer over.
    ///
    /// It prints as `ok`, which is the word a reader acts on — the case is named for what it *is*, so that it reads as the opposite of the one it is decided against.
    case unqualified(String)
    /// The call worked and the answer is qualified — every qualification named, then what it is an answer over.
    case qualified([String], detail: String)
    /// The answer could not be given honestly; the reason is why, and what would make it answerable.
    case refused(String)

    /// The verdict for an answer with these qualifications: unqualified when there are none, qualified otherwise.
    ///
    /// One constructor rather than an `if` at each face, because "no qualifications" and "ok" are the same fact and a face that got to decide the mapping could decide it differently.
    public static func reporting(qualifications: [String], detail: String) -> AnswerVerdict {
        qualifications.isEmpty ? .unqualified(detail) : .qualified(qualifications, detail: detail)
    }

    /// One qualification clause — `2 captures taken before the tree settled` — or nothing at all when there is none of that kind to state.
    ///
    /// Here rather than on each summary, where it was two verbatim copies: a clause that is *absent* when its count is zero is the contract's third rule in one line, and a second copy is where one of them starts printing `0 screens unreachable`.
    public static func qualification(_ count: Int, _ noun: String, _ clause: String) -> String? {
        count > 0 ? "\(count) \(noun)\(count == 1 ? "" : "s") \(clause)" : nil
    }

    /// The line as it is printed, the word first.
    public var line: String {
        switch self {
        case let .unqualified(detail):
            "ok — \(detail)"
        case let .qualified(qualifications, detail):
            "qualified — \(([qualifications.joined(separator: "; ")] + [detail]).filter { !$0.isEmpty }.joined(separator: " · "))"
        case let .refused(reason):
            "refused — \(reason)"
        }
    }

    /// How each of the three verdict lines opens, for a reader that has only the text and has to decide whether this tool answered at all.
    ///
    /// Derived from ``line`` rather than spelled a second time, so a verdict word cannot be renamed here and go on being recognised there. The status line's transcript scan is the caller: an errored tool result carrying one of these is an *answer* — `qualified` is exit 2 and a documented success, and `refused` is this tool declining, which is still a call it made and answered — where a result carrying none of them is a call that never ran, and the difference is whether it belongs in a count of what a session asked of this tool.
    public static var prefixes: [String] {
        [unqualified("").line, qualified([], detail: "").line, refused("").line]
    }

    /// Whether the call worked and the answer is qualified — the exit-2 question.
    public var isQualified: Bool {
        exitCode == Self.qualifiedExitCode
    }

    /// What a process reporting this verdict exits with.
    public var exitCode: Int32 {
        switch self {
        case .unqualified: 0
        case .qualified: Self.qualifiedExitCode
        case .refused: Self.refusedExitCode
        }
    }

    /// The call worked and the answer is qualified — distinct from a refusal, because those want different responses from a pipeline.
    public static let qualifiedExitCode: Int32 = 2

    /// The call could not be answered honestly.
    public static let refusedExitCode: Int32 = 1

    /// iPhone Mirroring was not frontmost (``MirrorFocusRefusal``): the one refusal whose right response is to retry, which is not true of a bad argument or a missing window, so a caller can branch on it without parsing a message.
    public static let notFrontmostExitCode: Int32 = 3
}
