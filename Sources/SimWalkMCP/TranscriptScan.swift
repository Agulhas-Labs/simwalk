//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Counts this tool's calls on a Claude Code transcript.
///
/// Both ways of reaching the tool are counted, because both are the session using it: an `mcp__simwalk__…` tool call, and a `Bash` call whose command names the binary. Only a call whose log line names the session can be priced — the MCP face always names it, and a shell call only where the `PreToolUse` hook left a slip for it to claim (``CallAttribution``, SimWalk#14) — but leaving shell calls out of the *count* would report a session that walked from the command line as one that never used the tool.
///
/// **A call the user denied is not a call the session made.** It is counted where the `tool_use` block appears, because that is the first line that can know about it, and taken back when its result says it never ran. A denial is told from a *refusal* by the answer's own wording rather than by the error flag alone: a walk that refused is a call this tool answered and belongs in the count, where a permission denial, a timeout or an interrupt is a call that never happened. A `tool_use` whose result never arrives stays counted — an interrupted session did make the call, and the alternative is dropping every call still in flight at the moment the status line renders.
public struct TranscriptScan {
    /// Folds one transcript line into `tally`, advancing `state`.
    public static func fold(line: Data, into tally: inout SessionTally, state: inout SessionScanState) {
        // A byte-level pre-filter before any JSON parse: transcripts run to tens of megabytes and almost
        // every line is prose that cannot contribute. A *result* carries no tool name, so the ids still
        // awaiting one are markers too — matching on those keeps the filter exact, since only the results
        // of calls this scan actually counted are ever parsed.
        guard mayContribute(line, awaiting: state.pending.keys) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else {
            return
        }
        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                count(block, into: &tally, state: &state)
            case "tool_result":
                settle(block, into: &tally, state: &state)
            default:
                continue
            }
        }
    }
}

public extension TranscriptScan {
    /// The CLI's top-level verbs — what tells a call to this tool from a mention of its name in a shell command.
    ///
    /// Spelled here rather than read off the command tree because `SimWalkMCP` cannot see the executable target that owns it. `SimWalkCommandTests` fails when the two disagree, which is the same guarantee from the one side that can have it.
    static var invocationVerbs: Set<String> {
        ["validate", "walk", "inspect", "bundle", "usage", "mcp", "statusline", "install-hook", "uninstall-hook", "prune", "hook", "lease", "session", "mirror", "device"]
    }

    /// The argument vectors a shell command hands this tool — one per invocation, each the words after the binary, verb first, as the shell will split them.
    ///
    /// The test for an invocation is ``invokesThisTool(_:)``'s, the binary in command position with one of its own verbs after it; this is the same test keeping the words it found. The `PreToolUse` hook matches a call to its process on them (SimWalk#14), so they stop where the process's `argv` would: at the end of the command, and at a redirection, which the shell takes for itself. A leading `~/` is expanded as the shell would expand it. What the shell rewrites beyond that — a variable, a glob — is kept as written and so matches no process, which leaves the call untagged rather than tagged wrongly.
    static func invocations(in command: String) -> [[String]] {
        let tokens = shellTokens(of: command)
        return commandPositions(in: tokens).compactMap { index in
            guard let candidate = wordToken(at: index, in: tokens), namesTheBinary(candidate),
                  let verb = wordToken(at: index + 1, in: tokens), invocationVerbs.contains(verb)
            else {
                return nil
            }
            var arguments: [String] = []
            var position = index + 1
            while let word = wordToken(at: position, in: tokens), !isRedirection(word) {
                arguments.append(expandingTilde(word))
                position += 1
            }
            return arguments
        }
    }

    /// Every command a shell command line runs, as the words from its command position up to the end of it or a redirection — whatever the binary.
    ///
    /// The same tokenizer and the same command positions as ``invocations(in:)``, so a name inside a quoted argument, a heredoc or a comment is not a command here either. A prefix that only decorates the command behind it is kept as a command of its own, and the command it decorates follows as another, so `sudo xcrun simctl …` yields both `sudo xcrun simctl …` and `xcrun simctl …`. The `PreToolUse` hook reads a hand-driven simulator off these (SimWalk#12).
    static func commands(in command: String) -> [[String]] {
        let tokens = shellTokens(of: command)
        return commandPositions(in: tokens).map { index in
            var words: [String] = []
            var position = index
            while let word = wordToken(at: position, in: tokens), !isRedirection(word) {
                words.append(word)
                position += 1
            }
            return words
        }
    }
}

extension TranscriptScan {
    /// Whether a word is a `VAR=value` assignment, which a shell reads as part of the command it precedes — or, standing alone as a command, as setting a variable for the commands after it, which is how the `PreToolUse` hook reads it (SimWalk#80).
    static func isAssignment(_ word: String) -> Bool {
        guard let first = word.first, first == "_" || (first.isASCII && first.isLetter),
              let equals = word.firstIndex(of: "=")
        else {
            return false
        }
        return word[word.startIndex ..< equals].allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}

private extension TranscriptScan {
    /// Counts a call to this tool, and remembers it until its result arrives.
    static func count(_ block: [String: Any], into tally: inout SessionTally, state: inout SessionScanState) {
        guard let name = block["name"] as? String else { return }
        let isWalk: Bool
        if let tool = mcpTool(named: name) {
            // A dry run is a call, never a walk: it captures nothing and costs seconds where a walk
            // costs minutes, so counting it among walks would overstate what the session actually ran.
            let input = block["input"] as? [String: Any]
            isWalk = tool == .walk && (input?["dryRun"]).flatMap(MCPToolInvocation.boolean) != true
        } else if name == "Bash", invokesThisTool(block["input"] as? [String: Any]) {
            isWalk = false
        } else {
            return
        }
        tally.calls += 1
        tally.walks += isWalk ? 1 : 0
        guard let id = block["id"] as? String else { return }
        state.pending[id] = isWalk
    }

    /// Closes out a counted call, taking it back when the result says it never ran.
    static func settle(_ block: [String: Any], into tally: inout SessionTally, state: inout SessionScanState) {
        guard let id = block["tool_use_id"] as? String,
              let wasWalk = state.pending.removeValue(forKey: id)
        else {
            return
        }
        guard block["is_error"] as? Bool == true, !answered(block) else { return }
        tally.calls -= 1
        tally.walks -= wasWalk ? 1 : 0
    }

    /// Whether an errored result is this tool *answering*, rather than the call never having run.
    ///
    /// **All three verdict words mean the tool ran**, and reading only for `refused` was a real bug: a shell `walk` that reached every screen but one exits **2**, which is a documented success, and Claude Code marks any non-zero exit as an error — so a session whose walks were all qualified showed no status line at all. The test is for a verdict of any kind, read off ``AnswerVerdict/prefixes`` so the words and the thing that recognises them cannot drift apart.
    ///
    /// Checked line by line rather than against the whole result, because a shell call's output carries the verdict among whatever else the process wrote. What carries no verdict at all — a permission denial, a timeout, an interrupt — is the call that never happened.
    static func answered(_ block: [String: Any]) -> Bool {
        resultText(of: block).contains(where: { text in
            text.split(whereSeparator: \.isNewline).contains(where: { line in
                let trimmed = String(line).trimmed
                return AnswerVerdict.prefixes.contains(where: { trimmed.hasPrefix($0) })
            })
        })
    }

    /// A tool result's text, which a transcript writes either as a bare string or as typed content blocks.
    static func resultText(of block: [String: Any]) -> [String] {
        if let text = block["content"] as? String {
            return [text]
        }
        guard let blocks = block["content"] as? [[String: Any]] else { return [] }
        return blocks.compactMap { $0["text"] as? String }
    }

    /// The verb an MCP call of this server's names, or `nil` for anybody else's tool.
    static func mcpTool(named name: String) -> SimWalkTool? {
        guard name.hasPrefix(toolPrefix) else { return nil }
        return SimWalkTool(rawValue: String(name.dropFirst(toolPrefix.count)))
    }

    /// The prefix this server's tools appear under in a transcript.
    static var toolPrefix: String {
        "mcp__\(SimWalkPaths.binaryName)__"
    }

    /// Whether a shell call *invoked* this tool, rather than merely naming its file.
    ///
    /// **Naming the binary is not calling it, and that distinction is the whole content of this.** A whole-word match on the name counted `ls -l ~/.local/bin/simwalk`, `cp .build/release/simwalk ~/.local/bin/` and `cat ~/.simwalk/usage.jsonl` as calls — so a session that checked the deploy and never walked anything read `simwalk 1 call`, which is exactly the dishonesty the answer contract means by a counter that only rises reading as adoption whatever the truth is.
    ///
    /// The test is the binary in **command position** with one of its own verbs after it: a word the shell would run as a command, whose last path component is the name however the path reached it, followed by a word that is a subcommand. Adjacency alone is not that test and reintroduces the same overcount by another door — `git commit -m "docs: simwalk usage reads the log"` and `grep -rn "simwalk walk" Docs/` are two words about this tool with no call between them. Command position is what tells them apart, and ``shellTokens(of:)`` is what makes it decidable.
    ///
    /// It is still not the "read the verb out of the command line" this deliberately avoided: it does not try to say *which* verb ran, only that one did, and the count stays a count of calls.
    ///
    /// The verbs are the CLI's top-level subcommands, held to it by ``SimWalkCommandTests`` so a new one cannot land without landing here. A verb this does not know undercounts, which is the one direction a count of the tool's own use is allowed to be wrong in.
    static func invokesThisTool(_ input: [String: Any]?) -> Bool {
        guard let command = input?["command"] as? String else { return false }
        return !invocations(in: command).isEmpty
    }

    /// Whether a word is a redirection — `>`, `2>`, `<file` — which the shell consumes rather than passing on.
    static func isRedirection(_ word: String) -> Bool {
        guard let first = word.drop(while: \.isNumber).first else { return false }
        return first == ">" || first == "<"
    }

    /// A word with a leading `~/` spelled out as the home directory it names, as the shell hands it on.
    static func expandingTilde(_ word: String) -> String {
        guard word.hasPrefix("~/") else { return word }
        return FileManager.default.homeDirectoryForCurrentUser.path + word.dropFirst()
    }

    /// Whether a word reaches this tool's binary, however the path spells the way to it.
    static func namesTheBinary(_ word: String) -> Bool {
        word.split(separator: "/").last.map(String.init) == SimWalkPaths.binaryName
    }

    /// The indices of the words a shell would run as a command: the first word, the first after each separator, and the first past a prefix that only decorates the command behind it.
    ///
    /// A prefix is transparent **only where it is itself in command position**, which is what keeps the rule from leaking: `sudo simwalk walk` is a call, and `echo sudo simwalk walk` is a sentence about one. The same holds for a `VAR=value` assignment, which prefixes a command only at the front of one — `make FOO=bar simwalk walk` passes two arguments to `make`.
    static func commandPositions(in tokens: [ShellToken]) -> [Int] {
        var positions: [Int] = []
        var isCommandPosition = true
        var index = 0
        while index < tokens.count {
            guard let word = wordToken(at: index, in: tokens) else {
                isCommandPosition = true
                index += 1
                continue
            }
            if isCommandPosition {
                positions.append(index)
                // `swift run simwalk walk` reaches the binary through a two-word prefix, so the pair is
                // stepped over together — `swift` alone decorates nothing.
                if word == "swift", wordToken(at: index + 1, in: tokens) == "run" {
                    index += 2
                    continue
                }
                isCommandPosition = isPrefix(word)
            }
            index += 1
        }
        return positions
    }

    /// Whether a word merely decorates the command that follows it rather than being one.
    static func isPrefix(_ word: String) -> Bool {
        commandPrefixes.contains(word) || isAssignment(word)
    }

    /// The single words that stand in front of the command they run.
    static var commandPrefixes: Set<String> {
        ["sudo", "env", "time", "exec", "xargs", "command", "nohup"]
    }

    /// The characters a backslash still escapes inside a double-quoted argument — everywhere else inside one it is a backslash the shell hands on as itself.
    static var doubleQuoteEscapes: Set<Character> {
        ["\"", "`", "$", "\\", "\n"]
    }

    /// The word at `index`, or `nil` where the token there is a separator or there is no token there.
    static func wordToken(at index: Int, in tokens: [ShellToken]) -> String? {
        guard tokens.indices.contains(index), case let .word(word) = tokens[index] else { return nil }
        return word
    }

    /// A shell command as words, with a separator wherever one command ends and the next begins.
    ///
    /// **Quoting groups, it does not split** — which is what closes the gap between naming this tool and calling it. `git commit -m "docs: simwalk usage reads the log"` carries the whole message as a single word, and a word that is a sentence is not a path to the binary; a quoted *path* is still the path it spells, so `"$HOME/.local/bin/simwalk" walk` reads as the invocation it is. Stripping the quotes off each whitespace-separated word instead cannot tell those two apart, because in `-m "docs: simwalk usage"` the word `simwalk` carries no quote of its own.
    ///
    /// **A quote ends where the shell ends it, not at the next quotation mark.** Escaping is honoured inside `"…"`, because a subject like `fix: "simwalk walk" is the call; simwalk usage is too` is written with `\"` and is ordinary practice in these repos. Ending the quote at the first `\"` hands the rest of the message back as shell, and the `;` in it reopens command position on prose — the same overcount this exists to remove, reached from inside a string.
    ///
    /// **A heredoc ends the scan where it opens.** Its body is text the shell hands to another program, but it is text laid out in command position — `exec simwalk statusline "$@"` inside the shim this tool's own installer writes is a line *about* the tool — and only the delimiter, on its own line, says where the body stops. Everything from `<<` on is dropped rather than parsed. That undercounts a command that carries on past the body, which is the direction this number is allowed to be wrong in, where reading the body counts calls nobody made.
    ///
    /// **A comment is not shell.** Everything from a `#` that opens a word to the end of its line is dropped, since the shell runs none of it — and a note like `# rebuild; simwalk walk book.yml` is otherwise words in command position with a separator among them.
    ///
    /// **A body is stored, not run.** A `(` or `{` is a separator only where it opens a group *and* the command behind it is not a function declaration; anything else it opens ends the scan, because the newline inside a function body would otherwise reopen command position on lines the shell is only remembering. Two cases reach that: one arriving mid-command, which opens something this cannot name — a body, an `-exec {}`, an `awk` program — and one at the start of a command whose look-back finds a declaration, which is the same body written with its brace on a line of its own. Only the separators that start a new command are separators: `|`, `&`, `;`, a newline, and that group-opening `(` or `{`. A redirection is deliberately not one — `cat > ~/.sift/statusline.d/simwalk` writes a file named after the tool and runs nothing.
    ///
    /// Between the two, every declaration bash accepts is covered — `sw()`, `sw ()`, `sw ( )`, `function sw` and `function sw()`, with the brace on the same line or its own — but only the last of those needs the look-back, and only for the `name()` and `function name` spellings it reads. Two things this deliberately cannot say, both measured: a body is dropped where it is *declared*, so a function that is genuinely called afterwards — `main() { simwalk walk; }` and then `main` — has its walk go uncounted, and a body ends the scan rather than being stepped over, so a real call after the closing brace is given up with it. Both undercount, which is the direction this is allowed to be wrong in.
    ///
    /// The `!hasWord` test that gates `#`, `(` and `{` is an **approximation** of "at the start of a token", and a knowing one. It is wrong where an operator this folds into a word butts straight against one of them: `ls >#foo; simwalk walk` and a `case` arm's `a)# note; simwalk walk` both still read the comment as shell. Carrying a redirection grammar to catch two malformed lines would cost more than it is worth — but the test is approximate rather than total, and a reader adding to it should know which.
    static func shellTokens(of command: String) -> [ShellToken] {
        var tokens: [ShellToken] = []
        var word = ""
        var hasWord = false
        var quote: Character?
        var isAnsiQuote = false
        let characters = Array(command)
        var index = 0

        func endWord() {
            guard hasWord else { return }
            tokens.append(ShellToken.word(word))
            word = ""
            hasWord = false
        }

        /// Whether nothing has been read since the last command ended, which is where a `(` or `{` opens a group the shell runs rather than a body it stores.
        func startsACommand() -> Bool {
            guard let last = tokens.last else { return true }
            if case .separator = last {
                return true
            }
            return false
        }

        /// Whether the command a `(` or `{` is starting is a function's body rather than a group.
        ///
        /// A brace written on a line of its own follows a separator exactly as a group's does, so the start of a command does not tell the two apart on its own — what does is the declaration one line further back, and it is read here in the two spellings that reach it: a name ending in `()`, and `function` before the name.
        func opensAStoredBody() -> Bool {
            var position = tokens.count - 1
            while position >= 0, case .separator = tokens[position] {
                position -= 1
            }
            guard position >= 0, case let .word(name) = tokens[position] else { return false }
            if name.hasSuffix("()") {
                return true
            }
            guard position > 0, case let .word(keyword) = tokens[position - 1] else { return false }
            return keyword == "function"
        }

        while index < characters.count {
            let character = characters[index]
            index += 1
            if let open = quote {
                // Inside `'…'` every character is itself, which is the whole of the POSIX rule. Inside `"…"`
                // a backslash keeps its meaning before the four characters that keep theirs, and before a
                // newline — so `\"` is a quotation mark *in* the argument and not the end of it, which is
                // what a commit subject quoting a command is made of. Inside bash's `$'…'` it escapes
                // whatever follows it, the apostrophe included.
                if character == "\\", index < characters.count,
                   isAnsiQuote || (open == "\"" && doubleQuoteEscapes.contains(characters[index]))
                {
                    let escaped = characters[index]
                    index += 1
                    if escaped != "\n" {
                        word.append(escaped)
                    }
                    continue
                }
                if character == open {
                    quote = nil
                    isAnsiQuote = false
                } else {
                    word.append(character)
                }
                continue
            }
            switch character {
            case "'", "\"":
                // An opening quote makes a word even before a character of it arrives, so `""` is the empty
                // argument it is rather than nothing at all.
                quote = character
                // `$'…'` is bash's ANSI-C quoting, and it is the one single-quoted form a backslash reaches
                // into: `$'don\'t forget; simwalk walk'` is one word, where reading the apostrophe as the
                // close of the quote hands the rest of the sentence back as shell.
                isAnsiQuote = character == "'" && word.last == "$"
                hasWord = true
            case "\\":
                // A backslash before a newline is a line continuation the shell removes; before anything
                // else it is that character, taken literally.
                guard index < characters.count else { break }
                let escaped = characters[index]
                index += 1
                if escaped != "\n" {
                    word.append(escaped)
                    hasWord = true
                }
            case "<" where index < characters.count && characters[index] == "<":
                endWord()
                return tokens
            case "#" where !hasWord:
                // A `#` that opens a word opens a comment, and a comment is text the shell never runs. It
                // read as ordinary words before, inert only until one of them held a `;` — at which point a
                // note somebody left themselves was counted as the call it was a note about. The newline
                // that ends it is left to end the command, which is what it does.
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
            case "|", "&", ";", "\n":
                endWord()
                tokens.append(ShellToken.separator)
            case "(" where !hasWord, "{" where !hasWord:
                // At the start of a command these open a group the shell runs, so what follows them stands
                // in command position. Anywhere else the lexer cannot say what they open — the body of a
                // function, which is stored and never run, an `-exec {}`, an `awk` program — and a body's
                // own newline would reopen command position on lines the shell is only remembering, which
                // is how `sw() {` over two lines counted a call that declaring a helper never makes. So the
                // scan ends here as it does at a heredoc: what is past it is given up rather than guessed
                // at, which undercounts and never counts a call nobody made.
                guard startsACommand(), !opensAStoredBody() else { return tokens }
                tokens.append(ShellToken.separator)
            default:
                if character.isWhitespace {
                    endWord()
                } else {
                    word.append(character)
                    hasWord = true
                }
            }
        }
        endWord()
        return tokens
    }

    /// Whether a line could hold anything countable, decided on raw bytes before anything parses it.
    static func mayContribute(_ line: Data, awaiting pending: some Collection<String>) -> Bool {
        if line.range(of: Data(SimWalkPaths.binaryName.utf8)) != nil {
            return true
        }
        return pending.contains { line.range(of: Data($0.utf8)) != nil }
    }

    /// One lexed piece of a shell command.
    enum ShellToken {
        /// A word as the shell would hand it on, with the quoting it would itself strip already taken off.
        case word(String)

        /// The end of one command and the start of the next, so whatever follows stands in command position.
        case separator
    }
}
