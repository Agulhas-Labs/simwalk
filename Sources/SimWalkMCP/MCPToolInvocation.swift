//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// One `tools/call`, resolved into the verb it names and the argument vector the CLI face parses.
///
/// **The MCP face does not have its own idea of what a walk's options are.** Its arguments are translated into the command line the same subcommand already defines, and that command parses them — so an option added to `walk` cannot be honoured by one face and unknown to the other, and a refusal like "`--settle 0` would be discarded" is the same refusal in both. What this type owns is only the translation: which JSON key becomes which flag, and which keys a call cannot omit.
///
/// **A caller's value can never be read as a flag.** Every option this builds carries its value attached — `--output=<path>`, never `--output <path>` — and every positional comes after a `--`, so a walkbook named `-x.json` is a walkbook, and a screen id spelled `--settle=0` is a screen id rather than a quiet period nobody asked for. Built the other way, a caller's value that looks like an option became one: the command then refused an argument the caller never sent, or rejected the vector outright, and the log recorded either as the caller's mistake.
///
/// **An argument that is present and unusable is refused, never dropped.** A `settle` of `0.5`, of `"900"` or of `true` is a caller asking for something, and walking at the default over it is the silent-discard failure this tool exists not to have — the same reasoning that made `--settle 0` a refusal rather than a fallback.
public struct MCPToolInvocation: Equatable, Sendable {
    /// The verb this call names.
    public let tool: SimWalkTool

    /// What the call was pointed at, for the usage log.
    public let target: String

    /// The command line the CLI face parses.
    public let argumentVector: [String]

    /// What this call is logged as: `tool.logName` for every verb but a screen-scoped `inspect`, which logs as `bundle screen` — so `simwalk usage` prices a one-screen answer against what it actually stood in for rather than folding it into `bundle inspect`'s figures.
    public let logName: String

    /// Resolves a raw `tools/call`, refusing a tool this server does not serve and any argument it cannot use.
    ///
    /// Every refusal is made here rather than downstream so the failure names the *call* — an unknown tool never reaches an exhaustive switch that would have to invent a case for it, and a missing path never reaches `URL(fileURLWithPath: "")`, which is a directory rather than an error.
    ///
    /// `mode` is the client's: a blocking client is not offered `walk_status`, so a call to it is an unknown tool, and the refusal lists the tools that client was offered.
    public init(tool name: String, arguments: [String: Any], mode: MCPClientMode = .blocking) throws {
        guard let tool = SimWalkTool(rawValue: name), mode == .bounded || tool != .walkStatus else {
            throw MCPError(message: "unknown tool '\(name)' — this server serves \(MCPToolCatalog.toolNames(for: mode).joined(separator: ", "))", kind: .inputRefused)
        }
        self.tool = tool
        switch tool {
        case .walk:
            let walkbook = try Self.path("walkbook", of: tool, in: arguments)
            target = walkbook
            let dryRun = try Self.dryRunFlag(arguments["dryRun"], of: tool)
            argumentVector = try [Self.attached("--output", Self.path("output", of: tool, in: arguments))]
                + Self.option("--device", "device", arguments["device"], of: tool)
                + Self.option("--lease", "lease", arguments["lease"], of: tool)
                + Self.option("--app-path", "appPath", arguments["appPath"], of: tool)
                + Self.option("--team", "team", arguments["team"], of: tool)
                + Self.option("--runner-bundle-id", "runnerBundleId", arguments["runnerBundleId"], of: tool)
                + Self.settle(arguments["settle"], of: tool)
                + Self.flag("--motion", "motion", arguments["motion"], of: tool)
                + Self.flag("--animations", "animations", arguments["animations"], of: tool)
                + Self.flag("--stock", "stock", arguments["stock"], of: tool)
                + Self.screenIDs(arguments["screenIDs"], of: tool)
                + dryRun
                + Self.flag("--verbose", "verbose", arguments["verbose"], of: tool)
                + Self.positional(walkbook)
            logName = dryRun.isEmpty ? tool.logName : SimWalkTool.walkDryRunLogName
        case .validate:
            let walkbook = try Self.path("walkbook", of: tool, in: arguments)
            target = walkbook
            argumentVector = try Self.flag("--device", "device", arguments["device"], of: tool) + Self.positional(walkbook)
            logName = tool.logName
        case .audit:
            let bundle = try Self.path("bundle", of: tool, in: arguments)
            target = bundle
            argumentVector = try Self.only(arguments["only"], of: tool)
                + Self.option("--walkbook", "walkbook", arguments["walkbook"], of: tool)
                + Self.positional(bundle)
            logName = tool.logName
        case .diff:
            let run = try Self.path("run", of: tool, in: arguments)
            target = run
            argumentVector = try Self.option("--crops", "crops", arguments["crops"], of: tool)
                + Self.positional(Self.path("reference", of: tool, in: arguments), run)
            logName = tool.logName
        case .oracle:
            let bundle = try Self.path("bundle", of: tool, in: arguments)
            target = bundle
            argumentVector = try [Self.attached("--walkbook", Self.path("walkbook", of: tool, in: arguments))] + Self.positional(bundle)
            logName = tool.logName
        case .inspect:
            let bundle = try Self.path("bundle", of: tool, in: arguments)
            target = bundle
            (argumentVector, logName) = try Self.inspectVector(bundle: bundle, arguments: arguments, of: tool)
        case .session:
            (argumentVector, target) = try Self.sessionVector(arguments)
            // Logged as `session <action>`, what the CLI logs; the action leads the vector.
            logName = ([tool.logName] + argumentVector.prefix(1)).joined(separator: " ")
        case .walkStatus:
            guard let handle = arguments["handle"] as? String else {
                throw MCPError(message: "walk_status needs a 'handle' string", kind: .inputRefused)
            }
            target = handle
            argumentVector = []
            logName = tool.logName
        case .mirror:
            (argumentVector, target) = try Self.mirrorVector(arguments)
            // Logged as `mirror <action>`, what the CLI logs; the action leads the vector.
            logName = ([tool.logName] + argumentVector.prefix(1)).joined(separator: " ")
        }
    }
}

private extension MCPToolInvocation {
    /// The arguments each `session` action takes; anything else beside `action` is refused by name rather than dropped.
    static let sessionArguments: [String: Set<String>] = [
        "start": ["app", "device", "lease", "state", "team", "runnerBundleId", "animations"],
        "read": ["id", "match"],
        "step": ["id", "step", "guard"],
        "save": ["id", "screen", "into", "expect", "since"],
        "end": ["id"],
        "list": [],
    ]

    /// `session`'s command line, and what it is pointed at.
    ///
    /// The action goes first — `simwalk session`'s own subcommand name, spelled here for the reason `"screen"` is — then that subcommand's options attached by `=`, its positionals after `--`. `step` and `state` arrive as JSON objects and are passed on as the JSON text the CLI takes.
    static func sessionVector(_ arguments: [String: Any]) throws -> (argumentVector: [String], target: String) {
        let tool = SimWalkTool.session
        guard let action = arguments["action"] as? String, let allowed = sessionArguments[action] else {
            let value = arguments["action"].map(described) ?? "none"
            throw MCPError(message: "session was given an 'action' of \(value) — it takes one of start, read, step, save, end, list", kind: .inputRefused)
        }
        if let stray = arguments.keys.filter({ $0 != "action" && !allowed.contains($0) }).sorted().first {
            throw MCPError(message: "session \(action) was given '\(stray)', which it does not take — it takes \(allowed.isEmpty ? "nothing beside 'action'" : allowed.sorted().map { "'\($0)'" }.joined(separator: ", "))", kind: .inputRefused)
        }
        if action == "list" {
            return ([action], "")
        }
        if action == "start" {
            let app = try path("app", of: tool, in: arguments)
            let vector = try [action, attached("--app", app)]
                + option("--device", "device", arguments["device"], of: tool)
                + option("--lease", "lease", arguments["lease"], of: tool)
                + object("--state", "state", arguments["state"], of: tool)
                + option("--team", "team", arguments["team"], of: tool)
                + option("--runner-bundle-id", "runnerBundleId", arguments["runnerBundleId"], of: tool)
                + flag("--animations", "animations", arguments["animations"], of: tool)
            return (vector, app)
        }
        let id = try path("id", of: tool, in: arguments)
        var vector = [action]
        var trailing: [String] = []
        switch action {
        case "read":
            vector += try option("--match", "match", arguments["match"], of: tool)
        case "step":
            guard let step = arguments["step"] else {
                throw MCPError(message: "session step needs 'step', which was not given", kind: .inputRefused)
            }
            vector += try option("--guard", "guard", arguments["guard"], of: tool)
            trailing = try [json(step, named: "step", of: tool)]
        case "save":
            vector += try [attached("--screen", path("screen", of: tool, in: arguments)), attached("--into", path("into", of: tool, in: arguments))]
                + option("--expect", "expect", arguments["expect"], of: tool)
                + since(arguments["since"], of: tool)
        default:
            break
        }
        return (vector + ["--", id] + trailing, id)
    }

    /// The arguments each `mirror` action takes; anything else beside `action` is refused by name rather than dropped.
    static let mirrorArguments: [String: Set<String>] = [
        "read": ["match", "settleMs", "out"],
        "tap": ["at", "match", "settleMs", "out"],
        "swipe": ["at", "to", "ms", "match", "settleMs", "out"],
        "scroll": ["lines", "horizontal", "at", "match", "settleMs", "out"],
        "menu": ["item", "match", "settleMs", "out"],
        "burst": ["at", "frames", "sheet", "out"],
    ]

    /// `mirror`'s command line, and what it is pointed at.
    ///
    /// The action first, then its options attached by `=`, then its positionals after `--` — so a negative `lines` is a number and not a flag. A fraction pair is passed on as written and range-checked by the command through `MirrorFraction`, the one place that refusal is made; this only insists it is two numbers.
    static func mirrorVector(_ arguments: [String: Any]) throws -> (argumentVector: [String], target: String) {
        let tool = SimWalkTool.mirror
        guard let action = arguments["action"] as? String, let allowed = mirrorArguments[action] else {
            let value = arguments["action"].map(described) ?? "none"
            throw MCPError(message: "mirror was given an 'action' of \(value) — it takes one of read, tap, swipe, scroll, menu, burst", kind: .inputRefused)
        }
        if let stray = arguments.keys.filter({ $0 != "action" && !allowed.contains($0) }).sorted().first {
            throw MCPError(message: "mirror \(action) was given '\(stray)', which it does not take — it takes \(allowed.sorted().map { "'\($0)'" }.joined(separator: ", "))", kind: .inputRefused)
        }
        var vector = [action]
        var positionals: [String] = []
        switch action {
        case "tap":
            positionals = try fractions("at", arguments, of: tool)
        case "swipe":
            positionals = try fractions("at", arguments, of: tool) + fractions("to", arguments, of: tool)
            vector += try whole("--ms", "ms", arguments["ms"], of: tool, within: MirrorGestureBounds.milliseconds, unit: "milliseconds")
        case "scroll":
            guard let lines = arguments["lines"] else {
                throw MCPError(message: "mirror scroll needs 'lines', which was not given", kind: .inputRefused)
            }
            guard let count = integer(lines) else {
                throw MCPError(message: "mirror was given a 'lines' of \(described(lines)) — it takes a whole number of wheel lines", kind: .inputRefused)
            }
            guard count != Int.min, MirrorGestureBounds.lines.contains(abs(count)) else {
                throw MCPError(message: "mirror was given a 'lines' of \(count) — it takes 1 to \(MirrorGestureBounds.lines.upperBound) wheel lines, negative for up or left; zero scrolls nothing", kind: .inputRefused)
            }
            positionals = [String(count)]
            vector += try flag("--horizontal", "horizontal", arguments["horizontal"], of: tool)
            if arguments["at"] != nil {
                try vector.append(attached("--at", fractions("at", arguments, of: tool).joined(separator: ",")))
            }
        case "menu":
            guard let item = arguments["item"] as? String, ["home", "switcher"].contains(item) else {
                throw MCPError(message: "mirror menu was given an 'item' of \(arguments["item"].map(described) ?? "none") — it takes home or switcher", kind: .inputRefused)
            }
            positionals = [item]
        case "burst":
            positionals = try fractions("at", arguments, of: tool)
            guard let frames = arguments["frames"] else {
                throw MCPError(message: "mirror burst needs 'frames', which was not given", kind: .inputRefused)
            }
            vector += try whole("--frames", "frames", frames, of: tool)
            vector += try flag("--sheet", "sheet", arguments["sheet"], of: tool)
        default:
            break
        }
        if action != "burst" {
            vector += try option("--match", "match", arguments["match"], of: tool)
            vector += try whole("--settle-ms", "settleMs", arguments["settleMs"], of: tool)
        }
        vector += try option("--out", "out", arguments["out"], of: tool)
        return (vector + ["--"] + positionals, ([action] + positionals).joined(separator: " "))
    }

    /// An `[x, y]` argument as the two numbers a command takes as positionals; anything but two JSON numbers is refused here, and a number outside `0…1` by the command.
    static func fractions(_ name: String, _ arguments: [String: Any], of tool: SimWalkTool) throws -> [String] {
        guard let value = arguments[name] else {
            throw MCPError(message: "\(tool.rawValue) needs '\(name)', which was not given", kind: .inputRefused)
        }
        let numbers = (value as? [Any])?.compactMap { element in
            (element as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue }
        }
        guard let numbers, numbers.count == 2, (value as? [Any])?.count == 2 else {
            throw MCPError(message: "\(tool.rawValue) was given an '\(name)' of \(described(value)) — it takes [x, y], two fractions of the window", kind: .inputRefused)
        }
        return numbers.map { String(describing: $0) }
    }

    /// An optional whole-number option, passed on attached: absent is the command's default, anything present has to be a whole number.
    ///
    /// `range` is the span the command accepts, refused here as `inputRefused` naming it, so a value the command would refuse is never reported as the server and the command disagreeing.
    static func whole(_ flag: String, _ name: String, _ value: Any?, of tool: SimWalkTool, within range: ClosedRange<Int>? = nil, unit: String = "") throws -> [String] {
        guard let value else { return [] }
        guard let number = integer(value) else {
            throw MCPError(message: "\(tool.rawValue) was given a '\(name)' of \(described(value)) — it takes a whole number", kind: .inputRefused)
        }
        if let range, !range.contains(number) {
            throw MCPError(message: "\(tool.rawValue) was given a '\(name)' of \(number) — it takes \(range.lowerBound) to \(range.upperBound) \(unit)", kind: .inputRefused)
        }
        return [attached(flag, String(number))]
    }

    /// A JSON object argument (`state`) as the JSON text its CLI option takes; absent is the command's default, anything but an object a refusal.
    static func object(_ flag: String, _ name: String, _ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        return try [attached(flag, json(value, named: name, of: tool))]
    }

    /// `value` as JSON text, when it is a JSON object.
    static func json(_ value: Any, named name: String, of tool: SimWalkTool) throws -> String {
        guard value is [String: Any], let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else {
            throw MCPError(message: "\(tool.rawValue) was given a '\(name)' of \(described(value)) — it takes a JSON object", kind: .inputRefused)
        }
        return text
    }

    /// `save`'s `since`: a whole request number, passed on for the command's own refusal of one below 1.
    static func since(_ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let number = integer(value) else {
            throw MCPError(message: "\(tool.rawValue) was given a 'since' of \(described(value)) — it takes a request number", kind: .inputRefused)
        }
        return [attached("--since", String(number))]
    }

    /// `inspect`'s own two shapes: the whole manifest, or — once `step` is given — one screen's text, run as `bundle screen` instead.
    ///
    /// `state`, `match`, `all`, `tree` and `bars` only mean anything beside `step`, so either arriving alone is refused rather than silently doing nothing, on the same "present and unusable is refused, never dropped" rule as every other argument here.
    ///
    /// `"screen"` is `BundleScreenCommand`'s own `commandName`, spelled here rather than referenced: this module cannot import `SimWalkCLI`, which is what hands the vector to that parser — the same reason `--device` and `--app-path` above are spelled rather than read off `WalkCommand`.
    static func inspectVector(bundle: String, arguments: [String: Any], of tool: SimWalkTool) throws -> (argumentVector: [String], logName: String) {
        guard let stepValue = arguments["step"] else {
            if let name = ["state", "match", "all", "tree", "bars"].first(where: { arguments[$0] != nil }) {
                throw MCPError(message: "\(tool.rawValue) was given '\(name)' without 'step' — it only applies when reading one screen", kind: .inputRefused)
            }
            return (Self.positional(bundle), tool.logName)
        }
        let step = try stepArgument(stepValue, of: tool)
        // `=` carries a value that looks like a flag past the parser — the same trap `settle` avoids
        // below. `BundleScreenCommand` parses both options unconditionally as well, which is what covers
        // a caller typing `--match -2` on a terminal; this form does not depend on it. The step goes last,
        // after `--`, so a screen id beginning with `--` is a step rather than an option the command refuses.
        let vector = try ["screen", bundle]
            + option("--state", "state", arguments["state"], of: tool)
            + option("--match", "match", arguments["match"], of: tool)
            + flag("--all", "all", arguments["all"], of: tool)
            + flag("--tree", "tree", arguments["tree"], of: tool)
            + flag("--bars", "bars", arguments["bars"], of: tool)
            + ["--", step]
        return (vector, BundleScreenQuery.logName)
    }

    /// `step` as the CLI's own positional: a screen's 1-based position, refused here when it is not a positive one — whether it arrived as a JSON number or as a string that reads as one (`"-1"`, which the schema's `["integer", "string"]` allows), so the refusal names the argument the caller wrote rather than anything a parser would have said — or the screen's own id, passed through as a caller wrote it.
    ///
    /// A string that reads as a position is passed on trimmed — `" 2 "` is step 2 for the lookup exactly as it is for the below-1 check, where passing it on untrimmed made it a screen id nothing has — but otherwise as written, never re-spelled from the number it reads as: `"007"` can be a screen's own id, which `"7"` is not, and the lookup reads a position out of either spelling.
    static func stepArgument(_ value: Any, of tool: SimWalkTool) throws -> String {
        if let position = integer(value) {
            return try positive(position, of: tool)
        }
        guard let id = value as? String, !id.trimmed.isEmpty else {
            throw MCPError(message: "\(tool.rawValue) was given a 'step' of \(described(value)) — it takes a screen's 1-based position, or its screen id", kind: .inputRefused)
        }
        if let position = Int(id.trimmed) {
            _ = try positive(position, of: tool)
            return id.trimmed
        }
        return id
    }

    /// A position as `step` passes it on, or the refusal of one below 1.
    static func positive(_ position: Int, of tool: SimWalkTool) throws -> String {
        guard position >= 1 else {
            throw MCPError(message: "\(tool.rawValue) was given a 'step' of \(position) — it takes a screen's 1-based position, or its screen id", kind: .inputRefused)
        }
        return String(position)
    }

    /// A required path argument, refused when it is absent, when it is not a string, and when it is blank.
    ///
    /// The three are told apart in the message because they are three different mistakes — one call forgot the argument, one passed something that is not a path, one computed an empty string for it — and only a message that says which sends the caller anywhere useful.
    static func path(_ name: String, of tool: SimWalkTool, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] else {
            throw MCPError(message: "\(tool.rawValue) needs '\(name)', which was not given", kind: .inputRefused)
        }
        guard let text = value as? String else {
            throw MCPError(message: "\(tool.rawValue) was given a '\(name)' of \(described(value)) — it takes a path", kind: .inputRefused)
        }
        guard !text.trimmed.isEmpty else {
            throw MCPError(message: "\(tool.rawValue) was given a blank '\(name)'", kind: .inputRefused)
        }
        return text
    }

    /// An optional string option: absent means the command's own default, and anything present has to be usable.
    ///
    /// The value is always attached by `=` on the same token as the flag (`--state=dark`), never as a second one — the form `--settle` uses below, and the one every option needs: a value that can begin with `-` (`--match -2 kg`) reads to ArgumentParser as `--match` given no value at all, where `--match=-2 kg` does not, and a caller's value could otherwise be read as the next flag.
    static func option(_ flag: String, _ name: String, _ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let text = value as? String, !text.trimmed.isEmpty else {
            throw MCPError(message: "\(tool.rawValue) was given a '\(name)' of \(described(value)) — it takes a non-empty string", kind: .inputRefused)
        }
        return [attached(flag, text)]
    }

    /// An option with its value attached by `=`, so the parser reads everything after the first `=` as the value — whatever it looks like.
    static func attached(_ flag: String, _ value: String) -> String {
        "\(flag)=\(value)"
    }

    /// A positional argument after the `--` terminator, the one place a value starting with `-` is never read as an option — last in the vector, because everything after the terminator is positional.
    static func positional(_ values: String...) -> [String] {
        ["--"] + values
    }

    /// The dry-run switch: `--dry-run` for a JSON `true`, nothing for `false`, and a refusal for anything else — a JSON `0` or `1` included (SimWalk#1 review).
    static func dryRunFlag(_ value: Any?, of tool: SimWalkTool) throws -> [String] {
        try flag("--dry-run", "dryRun", value, of: tool)
    }

    /// A switch: `flag` for a JSON `true`, nothing for `false`, and a refusal naming `key` for anything else.
    static func flag(_ flag: String, _ key: String, _ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let isOn = boolean(value) else {
            throw MCPError(message: "\(tool.rawValue) was given a '\(key)' of \(described(value)) — it takes true or false", kind: .inputRefused)
        }
        return isOn ? [flag] : []
    }

    /// The quiet period, passed as `--settle=<n>` so the command's own refusal of a non-positive one is what a caller sees.
    ///
    /// The `=` form every option here takes matters most for this one. `--settle -3` reads as an option with no value, so ArgumentParser refuses it as *missing a value* before `WalkCommand.validate()` ever gets to say that a non-positive quiet period would be discarded — and the caller reads the parser's sentence about its own syntax instead of the tool's sentence about their argument.
    ///
    /// **A JSON `null` is refused, deliberately.** It arrives as `NSNull` rather than as an absent key, which means the caller wrote something; the way to ask for the command's own default is to leave the key out, and treating the two alike would be the silent discard this whole type exists to refuse.
    static func settle(_ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let milliseconds = integer(value) else {
            throw MCPError(message: "\(tool.rawValue) was given a 'settle' of \(described(value)) — it takes a whole number of milliseconds", kind: .inputRefused)
        }
        return [attached("--settle", String(milliseconds))]
    }

    /// The screen subset, one attached `--screens=<id>` per id — the option collects every occurrence, and an id attached by `=` cannot be read as the next option.
    ///
    /// An empty array is the same request as no array — walk everything — and is the one shape here that is not a refusal, because nothing was asked for. An entry that is not a usable screen id is one, because something was.
    static func screenIDs(_ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let entries = value as? [Any] else {
            throw MCPError(message: "\(tool.rawValue) was given a 'screenIDs' of \(described(value)) — it takes an array of screen ids", kind: .inputRefused)
        }
        var ids: [String] = []
        for entry in entries {
            guard let id = entry as? String, !id.trimmed.isEmpty else {
                throw MCPError(message: "\(tool.rawValue) was given a 'screenIDs' entry of \(described(entry)) — every entry is a screen id", kind: .inputRefused)
            }
            ids.append(id)
        }
        guard !ids.isEmpty else { return [] }
        return ids.map { attached("--screens", $0) }
    }

    /// `audit`'s `only`: rule names, each becoming a repeat of `--only`.
    ///
    /// An empty array is every rule, as the flag's absence is.
    ///
    /// The names themselves are checked by the command, which owns the list — this module holds no copy to drift from it.
    static func only(_ value: Any?, of tool: SimWalkTool) throws -> [String] {
        guard let value else { return [] }
        guard let entries = value as? [Any] else {
            throw MCPError(message: "\(tool.rawValue) was given an 'only' of \(described(value)) — it takes an array of rule names", kind: .inputRefused)
        }
        var flags: [String] = []
        for entry in entries {
            guard let name = entry as? String, !name.trimmed.isEmpty else {
                throw MCPError(message: "\(tool.rawValue) was given an 'only' entry of \(described(entry)) — every entry is a rule name", kind: .inputRefused)
            }
            flags.append(attached("--only", name))
        }
        return flags
    }

    /// A JSON number that is a whole number this can carry exactly, and nothing else.
    ///
    /// `JSONSerialization` hands every number back as an `NSNumber`, and a bridged one answers `as? Int` for a boolean too — `true` becomes `1`, an argument nobody wrote. Core Foundation's type id is the only thing that tells a JSON `true` from a JSON `1`, so it is asked directly.
    ///
    /// **Beyond 2^53 the answer would be a neighbouring integer rather than the one written**, because that is where a `Double` stops representing consecutive integers — so a value that large is refused rather than rounded into a quiet period nobody asked for. Within the range, comparing the integer against its own `Double` is what catches `0.5`, which bridges just as willingly as a whole number does.
    static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let exact = number.int64Value
        guard exact.magnitude < exactIntegerLimit, Double(exact) == number.doubleValue else { return nil }
        return Int(exact)
    }

    /// 2^53 — above this a `Double` no longer represents every integer, so a number this large cannot be read back as the one that was written.
    static var exactIntegerLimit: UInt64 {
        1 << 53
    }

    /// The offending value as a refusal can quote it — bounded, because an argument can be arbitrarily large and a refusal is not the place to reprint one.
    ///
    /// Quoted the way JSON writes it, because the two mistakes worth telling apart look identical otherwise: `NSNumber` describes `true` as `1`, and a bare `900` in a refusal is the same text whether the caller sent the number or the string. A message that cannot distinguish `900` from `"900"` sends somebody looking at the wrong half of their call.
    static func described(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if let text = value as? String {
            return "\"\(bounded(text))\""
        }
        return bounded(String(describing: value))
    }

    static func bounded(_ text: String) -> String {
        text.count > 60 ? text.prefix(59) + "…" : text
    }
}

extension MCPToolInvocation {
    /// A JSON boolean, and nothing else.
    ///
    /// The mirror of `integer(_:)`: a bridged `NSNumber` answers `as? Bool` for a JSON `0` or `1` too, so `"dryRun": 0` would silently run a full walk that takes minutes and writes a bundle. Core Foundation's type id is what tells a JSON `true` from a JSON `1`.
    static func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
