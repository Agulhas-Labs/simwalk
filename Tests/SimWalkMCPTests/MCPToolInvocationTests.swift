//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// The translation from a JSON tool call to the command line the CLI face parses — the whole of what the MCP face owns about a verb's options.
struct MCPToolInvocationTests {
    /// `oracle` puts its walkbook attached ahead of the terminator and the bundle after it, and logs as the CLI verb.
    @Test
    func anOracleCallBuildsTheCommandLineOfBundleOracle() throws {
        let oracle = try MCPToolInvocation(tool: "oracle", arguments: ["bundle": "-x.simwalk", "walkbook": "--wb.json"])

        #expect(oracle.argumentVector == ["--walkbook=--wb.json", "--", "-x.simwalk"])
        #expect(oracle.logName == "bundle oracle")
        #expect(oracle.target == "-x.simwalk")
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "oracle", arguments: ["bundle": "x.simwalk"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "oracle", arguments: ["walkbook": "w.json"]) }
    }

    @Test
    func everyWalkOptionReachesTheCommandLineTheCLIDefines() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json",
            "output": "out.simwalk",
            "device": "iPhone 17 Pro",
            "appPath": "/build/App.app",
            "settle": 800,
            "motion": true,
            "animations": true,
            "stock": true,
            "screenIDs": ["today", "steps-detail"],
            "verbose": true,
        ])

        #expect(invocation.tool == .walk)
        #expect(invocation.target == "example.json")
        #expect(invocation.argumentVector == [
            "--output=out.simwalk",
            "--device=iPhone 17 Pro",
            "--app-path=/build/App.app",
            "--settle=800",
            "--motion",
            "--animations",
            "--stock",
            "--screens=today", "--screens=steps-detail",
            "--verbose",
            "--", "example.json",
        ])
    }

    /// A physical device's walk and the validate check for it reach the command line the CLI defines (SimWalk#116).
    @Test
    func theDeviceWalkOptionsAndValidateDeviceReachTheCommandLine() throws {
        let walk = try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "w.json", "output": "out.simwalk", "device": "00008160-00000000000000AA", "team": "TEAM", "runnerBundleId": "com.team.runner"])
        let validate = try MCPToolInvocation(tool: "validate", arguments: ["walkbook": "w.json", "device": true])

        #expect(walk.argumentVector == ["--output=out.simwalk", "--device=00008160-00000000000000AA", "--team=TEAM", "--runner-bundle-id=com.team.runner", "--", "w.json"])
        #expect(validate.argumentVector == ["--device", "--", "w.json"])
    }

    /// A `motion` that is not a Boolean is refused naming the key, never read as off: `"yes"` is a caller asking for it (SimWalk#67).
    @Test
    func amotionThatIsNotABooleanIsRefused() {
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "example.json", "output": "out.simwalk", "motion": "yes"])
        }
        #expect(throws: Never.self) {
            try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "example.json", "output": "out.simwalk", "motion": false])
        }
    }

    /// A lease token reaches the walk as `--lease`, so an agent on the MCP face walks its leased device as one on the CLI does.
    @Test
    func aleaseTokenReachesTheWalkAsItsOwnOption() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "example.json", "output": "out.simwalk", "lease": "TOKEN-1"])

        #expect(invocation.argumentVector == ["--output=out.simwalk", "--lease=TOKEN-1", "--", "example.json"])
    }

    /// The walkbook comes last, after the `--` terminator, because everything after one is positional — and every option before it carries its value attached, so nothing the caller sent can be read as the next option.
    @Test
    func thewalkbookIsTheLastThingOnTheCommandLineAfterTheTerminator() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json",
            "output": "out.simwalk",
            "screenIDs": ["today"],
            "device": "iPhone 17 Pro",
        ])

        #expect(invocation.argumentVector.suffix(2) == ["--", "example.json"])
        #expect(invocation.argumentVector.dropLast(2).allSatisfy { $0.hasPrefix("--") && $0.contains("=") })
    }

    /// **A caller's value is never read as a flag.** A screen id spelled like an option is a screen id: built as `--screens a --settle=0`, the command read a quiet period the caller never sent and refused *that*, in the caller's name.
    @Test
    func ascreenIDThatLooksLikeAnOptionStaysAScreenID() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json",
            "output": "out.simwalk",
            "screenIDs": ["--settle=0"],
        ])

        #expect(invocation.argumentVector == ["--output=out.simwalk", "--screens=--settle=0", "--", "example.json"])
    }

    /// A walkbook whose name starts with `-` is still a walkbook, on both verbs that take one: without the terminator the parser read `-x.json` as an unknown flag and `--version` as its own, and refused a vector this server built.
    @Test
    func awalkbookNamedLikeAnOptionIsPassedAfterTheTerminator() throws {
        let walk = try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "-x.json", "output": "out.simwalk"])
        let validate = try MCPToolInvocation(tool: "validate", arguments: ["walkbook": "--version"])

        #expect(walk.argumentVector.suffix(2) == ["--", "-x.json"])
        #expect(validate.argumentVector == ["--", "--version"])
    }

    /// `inspect` and `audit` take one positional too, and it was built without the terminator: `inspect {"bundle":"-x.simwalk"}` refused with "Missing expected argument '<bundle>'" and `audit {"bundle":"--help"}` printed the command's own help text — both logged as `tool-error` over a call that never reached a bundle at all.
    @Test
    func abundleNamedLikeAnOptionIsPassedAfterTheTerminator() throws {
        let inspect = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "-x.simwalk"])
        let audit = try MCPToolInvocation(tool: "audit", arguments: ["bundle": "--help"])

        #expect(inspect.argumentVector == ["--", "-x.simwalk"])
        #expect(audit.argumentVector == ["--", "--help"])
    }

    /// An argument that was never given is the command's own default; an *empty* screen subset is the same request as none, because nothing was asked for.
    @Test
    func anOmittedOptionIsOmittedRatherThanPassedEmpty() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json",
            "output": "out.simwalk",
            "screenIDs": [String](),
        ])

        #expect(invocation.argumentVector == ["--output=out.simwalk", "--", "example.json"])
    }

    /// **A present argument this cannot use is refused, never dropped.** JSON hands every number over as an `NSNumber`, and a bridged one will answer `as? Int` for `true` — so `settle: true` would silently become 1ms and `settle: 0.5` would silently become the default, which is the silent-discard failure `--settle 0` was made a refusal to prevent.
    @Test
    func asettleThatIsNotAWholeNumberOfMillisecondsIsRefusedRatherThanDropped() throws {
        for unusable in [0.5, "900", true, ["900"]] as [Any] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "walk", arguments: [
                    "walkbook": "example.json", "output": "out.simwalk", "settle": unusable,
                ])
            }

            #expect(thrown?.message.contains("'settle'") == true)
            #expect(thrown?.message.contains("whole number of milliseconds") == true)
        }
    }

    /// A refusal quotes what the caller wrote: `NSNumber` describes `true` as `1`, and a message about `1` sends somebody looking for a number they never passed.
    @Test
    func arefusalQuotesTheArgumentAsItWasWritten() {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: [
                "walkbook": "example.json", "output": "out.simwalk", "settle": true,
            ])
        }

        #expect(thrown?.message.contains("of true") == true)
    }

    /// A refusal that cannot tell `900` from `"900"` sends somebody looking at the wrong half of their call, so a string is quoted the way JSON writes it.
    @Test
    func arefusalTellsAStringArgumentFromTheNumberItLooksLike() {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: [
                "walkbook": "example.json", "output": "out.simwalk", "settle": "900",
            ])
        }

        #expect(thrown?.message.contains("of \"900\"") == true)
    }

    /// Above 2^53 a `Double` no longer represents consecutive integers, so the walk would run at a neighbouring quiet period nobody asked for — which is the silent change this refuses everywhere else.
    @Test
    func asettleTooLargeToCarryExactlyIsRefusedRatherThanRounded() throws {
        let representable = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json", "output": "out.simwalk", "settle": 9_007_199_254_740_991,
        ])

        #expect(representable.argumentVector.contains("--settle=9007199254740991"))
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: [
                "walkbook": "example.json", "output": "out.simwalk", "settle": 9_007_199_254_740_993,
            ])
        }
    }

    /// A JSON `null` arrives as `NSNull` rather than as an absent key, so the caller wrote something — and the way to ask for the command's own default is to leave the key out.
    @Test
    func anExplicitNullIsRefusedRatherThanReadAsAbsent() {
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: [
                "walkbook": "example.json", "output": "out.simwalk", "settle": NSNull(),
            ])
        }
    }

    /// `--settle -3` reads as an option with no value, so the `=` form is what gets a negative one past the parser and into the command's own refusal.
    @Test
    func anegativeSettleReachesTheCommandsOwnRefusalRatherThanTheParsers() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json", "output": "out.simwalk", "settle": -3,
        ])

        #expect(invocation.argumentVector.contains("--settle=-3"))
    }

    @Test
    func ascreenSubsetThatIsNotAListOfIdsIsRefused() throws {
        for unusable in ["today", 3, ["today", 7], [""], [" "]] as [Any] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "walk", arguments: [
                    "walkbook": "example.json", "output": "out.simwalk", "screenIDs": unusable,
                ])
            }

            #expect(thrown?.message.contains("'screenIDs'") == true)
        }
    }

    @Test
    func anOptionalStringOptionThatIsPresentAndUnusableIsRefused() throws {
        for unusable in ["  ", 3, true] as [Any] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "walk", arguments: [
                    "walkbook": "example.json", "output": "out.simwalk", "device": unusable,
                ])
            }

            #expect(thrown?.message.contains("'device'") == true)
        }
    }

    @Test
    func theBundleVerbsCarryTheCLIsOwnNameForThemIntoTheLog() throws {
        let inspect = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk"])
        let audit = try MCPToolInvocation(tool: "audit", arguments: ["bundle": "x.simwalk"])

        #expect(inspect.tool.logName == "bundle inspect")
        #expect(audit.tool.logName == "bundle audit")
        // Round 5, finding 2: the bundle positional comes after the `--` terminator too, so a bundle
        // named like an option is never read as one.
        #expect(inspect.argumentVector == ["--", "x.simwalk"])
        #expect(audit.argumentVector == ["--", "x.simwalk"])
    }

    /// `only` becomes one `--only=<rule>` per entry, attached like every other option and ahead of the terminator.
    @Test
    func anOnlyArrayBecomesRepeatedAttachedOnlyFlagsBeforeTheTerminator() throws {
        let audit = try MCPToolInvocation(tool: "audit", arguments: ["bundle": "x.simwalk", "only": ["unlabelledControl", "duplicateLabel"]])

        #expect(audit.argumentVector == ["--only=unlabelledControl", "--only=duplicateLabel", "--", "x.simwalk"])
    }

    /// `diff` puts its optional `crops` attached ahead of the terminator and both bundles after it, reference first.
    @Test
    func aDiffCarriesItsCropsAttachedAndBothBundlesAfterTheTerminator() throws {
        let plain = try MCPToolInvocation(tool: "diff", arguments: ["reference": "a.simwalk", "run": "b.simwalk"])
        let cropped = try MCPToolInvocation(tool: "diff", arguments: ["reference": "a.simwalk", "run": "b.simwalk", "crops": "out"])

        #expect(plain.argumentVector == ["--", "a.simwalk", "b.simwalk"])
        #expect(cropped.argumentVector == ["--crops=out", "--", "a.simwalk", "b.simwalk"])
        #expect(cropped.target == "b.simwalk")
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "diff", arguments: ["reference": "a.simwalk"]) }
    }

    @Test
    func anOnlyThatIsNotAnArrayOfNamesIsRefused() {
        for bad: Any in ["unlabelledControl", 3, ["ok", 4], [""]] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "audit", arguments: ["bundle": "x.simwalk", "only": bad])
            }
            #expect(thrown?.kind == .inputRefused)
            #expect(thrown?.message.contains("'only'") == true)
        }
    }

    /// `step` turns `inspect` into `bundle screen`: the vector leads with that command's own name, and the call logs as the verb it actually ran rather than as a whole-bundle inspect.
    ///
    /// `--state` and `--match` carry their value on the same token as the flag — `=dark`, not a second array element — the same trap `--settle`'s own `=` form avoids (SimWalk#20 round 2, finding 3). The step comes last, after `--`, so whatever it spells it is a step (SimWalk#20 round 4, finding 8 — the vectors in these tests gained the terminator then).
    @Test
    func astepArgumentBuildsTheScreenCommandsOwnVectorAndLogsAsScreen() throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: [
            "bundle": "x.simwalk", "step": 3, "state": "dark", "match": "Cycling",
        ])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--state=dark", "--match=Cycling", "--", "3"])
        #expect(invocation.logName == "bundle screen")
        #expect(invocation.target == "x.simwalk")
    }

    /// A `--match` (or `--state`) beginning with `-` reaches the command as one token rather than being read by the parser as an option with no value — the failure mode a plain `--match value` pair hits on `-2 kg`.
    @Test
    func amatchBeginningWithADashSurvivesAsOneJoinedToken() throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: [
            "bundle": "x.simwalk", "step": 1, "match": "-2 kg",
        ])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--match=-2 kg", "--", "1"])
    }

    /// `state` and `match` are optional even once `step` is given — omitting them omits the flags rather than passing an empty string.
    @Test
    func stateAndMatchAreOmittedWhenNotGiven() throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": 1])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--", "1"])
    }

    /// `step` also accepts the screen's own id — any non-empty string that is not itself refused as an unusable type — passed through as the caller wrote it rather than requiring a position (SimWalk#20 round 2, finding 4).
    @Test
    func astepGivenAsAStringIsPassedThroughAsAScreenID() throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": "sleep-detail"])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--", "sleep-detail"])
    }

    /// A `step` below 1 is refused here, in the invocation's own words, rather than reaching ArgumentParser as a bare `-1` — which it reads as an option missing its value before the command's own `<step>` refusal ever gets a turn (SimWalk#20 round 2, finding 3).
    @Test
    func astepBelowOneIsRefusedHereRatherThanReachingTheParserAsADash() throws {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": -1])
        }

        #expect(thrown?.message.contains("'step'") == true)
        #expect(thrown?.message.contains("-1") == true)
    }

    /// The schema allows `step` as a string too, so a string that reads as a position below 1 — `"-1"`, `"0"` — is refused here in the same words as the number, rather than passed through as an id for the parser to misread (SimWalk#20 round 3, finding 4).
    @Test(arguments: ["-1", "0", " -3"])
    func astepStringThatReadsAsAPositionBelowOneIsRefusedLikeTheNumber(_ step: String) throws {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": step])
        }

        #expect(thrown?.message.contains("was given a 'step' of \(step.trimmingCharacters(in: .whitespaces))") == true)
        #expect(thrown?.message.contains("1-based position") == true)
    }

    /// A step string that reads as a valid position is passed on as that position's own spelling — nothing about the refusal above narrows what an ordinary call can say — and trimmed, as the below-1 check already read it: `" 2 "` passed on untrimmed was a screen id nothing has (SimWalk#20 round 4, finding 9).
    @Test(arguments: ["3", " 3 "])
    func astepStringThatReadsAsAValidPositionIsPassedOnTrimmed(_ step: String) throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": step])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--", "3"])
    }

    /// A step string that reads as a position keeps its own spelling — `"007"` can be a screen's id, which `"7"` is not — and the lookup reads the position out of it either way (SimWalk#20 round 4, finding 9: this was passed on as `7`).
    @Test(arguments: ["007", "+3"])
    func astepStringThatReadsAsAPositionKeepsItsSpelling(_ step: String) throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": step])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--", step])
    }

    /// A `step` that is neither a whole number nor a usable string is refused rather than truncated or dropped.
    @Test
    func astepThatIsNeitherAWholeNumberNorAUsableStringIsRefused() {
        for unusable in [0.5, true] as [Any] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": unusable])
            }

            #expect(thrown?.message.contains("'step'") == true)
        }
    }

    /// `all` is a switch: `true` adds `--all` to `bundle screen`, `false` adds nothing (SimWalk#101).
    @Test
    func allIsAFlagBesideStep() throws {
        let listed = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": 1, "all": true])
        let unlisted = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": 1, "all": false])

        #expect(listed.argumentVector == ["screen", "x.simwalk", "--all", "--", "1"])
        #expect(unlisted.argumentVector == ["screen", "x.simwalk", "--", "1"])
    }

    /// `tree` and `bars` are switches beside `step` and reach `bundle screen` as `--tree` and `--bars` (SimWalk#121).
    @Test
    func treeAndBarsReachTheQuery() throws {
        let invocation = try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", "step": 1, "match": "Rows", "tree": true, "bars": true])

        #expect(invocation.argumentVector == ["screen", "x.simwalk", "--match=Rows", "--tree", "--bars", "--", "1"])
    }

    /// `state` and `match` only mean anything beside `step`; either arriving alone is refused rather than silently doing nothing, on the same rule as every other argument here.
    @Test
    func stateOrMatchWithoutStepIsRefused() {
        for name in ["state", "match", "all", "tree", "bars"] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "x.simwalk", name: ["all", "tree", "bars"].contains(name) ? true : "light"])
            }

            #expect(thrown?.message.contains("'\(name)'") == true)
            #expect(thrown?.message.contains("'step'") == true)
        }
    }

    @Test
    func amissingRequiredArgumentIsRefusedByName() {
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "example.json"])
        }
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "validate", arguments: [:])
        }
    }

    /// A blank path is refused rather than passed on, because `URL(fileURLWithPath: "")` is a directory rather than an error and the refusal downstream would be about the wrong thing.
    @Test
    func ablankRequiredArgumentIsRefusedRatherThanPassedOn() {
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "inspect", arguments: ["bundle": "   "])
        }
    }

    @Test
    func atoolThisServerDoesNotServeIsRefusedWhereItArrives() {
        #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "diff", arguments: ["bundle": "x.simwalk"])
        }
    }

    /// `dryRun: true` reaches the command line as `--dry-run`, after the other options and before the walkbook's own terminator, and the call logs as the dry run rather than as a walk.
    @Test
    func adryRunTrueAddsTheFlagAndLogsAsADryRun() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json", "output": "report.json", "dryRun": true,
        ])

        #expect(invocation.argumentVector == ["--output=report.json", "--dry-run", "--", "example.json"])
        #expect(invocation.logName == SimWalkTool.walkDryRunLogName)
    }

    /// `dryRun` omitted or `false` is a walk like any other, and never adds the flag.
    @Test
    func adryRunAbsentOrFalseIsAnOrdinaryWalk() throws {
        for arguments: [String: Any] in [
            ["walkbook": "example.json", "output": "out.simwalk"],
            ["walkbook": "example.json", "output": "out.simwalk", "dryRun": false],
        ] {
            let invocation = try MCPToolInvocation(tool: "walk", arguments: arguments)

            #expect(invocation.argumentVector == ["--output=out.simwalk", "--", "example.json"])
            #expect(invocation.logName == SimWalkTool.walk.logName)
        }
    }

    /// A non-boolean `dryRun` is refused like any other mistyped argument, rather than read as truthy.
    @Test
    func adryRunThatIsNotABooleanIsRefused() throws {
        for unusable in ["true", 1, NSNumber(value: 1), NSNumber(value: 0), ["true"]] as [Any] {
            let thrown = #expect(throws: MCPError.self) {
                try MCPToolInvocation(tool: "walk", arguments: [
                    "walkbook": "example.json", "output": "out.simwalk", "dryRun": unusable,
                ])
            }

            #expect(thrown?.message.contains("'dryRun'") == true)
            #expect(thrown?.message.contains("true or false") == true)
        }
    }

    /// Each `session` action builds `simwalk session <action>`'s own command line and logs as the CLI does; `step` and `state` objects go on as JSON text.
    @Test
    func eachSessionActionBuildsItsSubcommandsCommandLine() throws {
        let start = try MCPToolInvocation(tool: "session", arguments: ["action": "start", "app": "dev.x", "device": "UDID", "state": ["theme": "dark"]])
        let step = try MCPToolInvocation(tool: "session", arguments: ["action": "step", "id": "s1", "step": ["openURL": ["url": "x://d"]], "guard": "1a2b3c4d"])
        let save = try MCPToolInvocation(tool: "session", arguments: ["action": "save", "id": "s1", "screen": "d", "into": "w.json", "expect": "route-detail", "since": 3])
        let list = try MCPToolInvocation(tool: "session", arguments: ["action": "list"])

        #expect(start.argumentVector == ["start", "--app=dev.x", "--device=UDID", #"--state={"theme":"dark"}"#])
        #expect(start.target == "dev.x")
        #expect(step.argumentVector == ["step", "--guard=1a2b3c4d", "--", "s1", #"{"openURL":{"url":"x://d"}}"#])
        #expect(step.logName == "session step")
        #expect(save.argumentVector == ["save", "--screen=d", "--into=w.json", "--expect=route-detail", "--since=3", "--", "s1"])
        #expect(try MCPToolInvocation(tool: "session", arguments: ["action": "read", "id": "s1", "match": "-2"]).argumentVector == ["read", "--match=-2", "--", "s1"])
        #expect(try MCPToolInvocation(tool: "session", arguments: ["action": "end", "id": "s1"]).argumentVector == ["end", "--", "s1"])
        #expect(list.argumentVector == ["list"])
        #expect(list.logName == "session list")
    }

    /// `animations` on a `session start` becomes `--animations` when true, nothing when false; any other action refuses it by name (SimWalk#154).
    @Test
    func aSessionStartCarriesAnimationsAndOtherActionsRefuseIt() throws {
        let asked = try MCPToolInvocation(tool: "session", arguments: ["action": "start", "app": "dev.x", "device": "UDID", "animations": true])
        let off = try MCPToolInvocation(tool: "session", arguments: ["action": "start", "app": "dev.x", "device": "UDID", "animations": false])

        #expect(asked.argumentVector == ["start", "--app=dev.x", "--device=UDID", "--animations"])
        #expect(off.argumentVector == ["start", "--app=dev.x", "--device=UDID"])
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "read", "id": "s1", "animations": true]) }
    }

    /// `team` and `runnerBundleId` on a `session start` become `--team` and `--runner-bundle-id`; any other action refuses them by name.
    @Test
    func aSessionStartCarriesTeamAndRunnerBundleIDAndOtherActionsRefuseThem() throws {
        let start = try MCPToolInvocation(tool: "session", arguments: ["action": "start", "app": "dev.x", "device": "UDID", "team": "TEAM1", "runnerBundleId": "dev.x.runner"])

        #expect(start.argumentVector == ["start", "--app=dev.x", "--device=UDID", "--team=TEAM1", "--runner-bundle-id=dev.x.runner"])

        for stray in ["team", "runnerBundleId"] {
            let thrown = #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "read", "id": "s1", stray: "x"]) }
            #expect(thrown?.message.contains("'\(stray)'") == true)
        }
    }

    /// An unknown action, an argument the action does not take, and a `step` that is not an object are refused, never dropped.
    @Test
    func aSessionCallThatCannotBeMadeIsRefused() {
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "poke"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["id": "s1"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "read", "id": "s1", "guard": "1a2b3c4d"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "step", "id": "s1", "step": #"{"back":{}}"#]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "step", "id": "s1"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "session", arguments: ["action": "save", "id": "s1", "screen": "d", "into": "w.json", "since": "3"]) }
    }

    /// `audit`'s `walkbook` becomes an attached `--walkbook`, ahead of the terminator.
    @Test
    func anAuditCallCarriesItsWalkbookAsAnAttachedOption() throws {
        let audit = try MCPToolInvocation(tool: "audit", arguments: ["bundle": "x.simwalk", "walkbook": "--wb.json"])

        #expect(audit.argumentVector == ["--walkbook=--wb.json", "--", "x.simwalk"])
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "audit", arguments: ["bundle": "x.simwalk", "walkbook": 3]) }
    }
}
