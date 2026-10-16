//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `simwalk device walk` (SimWalk#116): what it refuses before it touches the phone, the order of what it runs, and what it will not call this walk's own.
struct DeviceWalkCommandTests {
    static var udid: String {
        "00008160-00000000000000AA"
    }

    static var plainWalkbook: String {
        #"{"name":"w","appBundleID":"x.y","screens":[{"id":"today","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
    }

    static let list = """
    {"result":{"devices":[{"properties":{
      "hardware":{"reality":"physical","udid":"\(udid)","marketingName":"iPhone 17","productType":"iPhone18,1"},
      "connection":{"transportType":"wired","pairingState":"paired","state":"connected"},
      "state":{"name":"Test Phone","developerModeStatus":{"enabled":"enabled"}},
      "software":{"osVersionNumber":{"stringValue":"27.0"}}}}]}}
    """

    private static func mode(of call: Call) -> String? {
        call.arguments.firstIndex(of: "--mode").map { call.arguments[$0 + 1] }
    }

    static func appearance(_ style: String, textSize: String = "Large") -> String {
        #"{"result":{"userInterfaceStyle":"\#(style)","textSize":"\#(textSize)","increaseContrast":false}}"#
    }

    /// A real bundle on disk carrying `nonce` and the device placeholder build hash, kept alive by the returned directory.
    static func bundle(nonce: String?, buildHash: String, provenance: CaptureManifest.AppBuildProvenance? = nil, in directory: TemporaryDirectory) throws -> URL {
        let capture = CaptureBundleFixture.Capture(
            screenID: "today",
            state: Walkbook.CaptureState(theme: .light),
            tree: FigureFixture.screen(text: "2,703")
        )
        return try CaptureBundleFixture.write(in: directory, captures: [capture], buildHash: buildHash, nonce: nonce, appBuildProvenance: provenance).url
    }

    /// `dropsProvenance` is a runner that predates `SIMWALK_BUILD_PROVENANCE`: it ignores the variable and writes none.
    func phone(appearances: [String], nonceOverride: String? = nil, dropsProvenance: Bool = false, keep: TemporaryDirectory) -> Phone {
        Phone(appearances: appearances) { nonce, buildHash, provenance in
            let directory = try TemporaryDirectory()
            // The bundle outlives this closure only until it is copied, so the scratch is held by `keep`'s lifetime via the copy below.
            let url = try Self.bundle(nonce: nonceOverride ?? nonce, buildHash: buildHash, provenance: dropsProvenance ? nil : provenance.flatMap(CaptureManifest.AppBuildProvenance.init(rawValue:)), in: directory)
            let staged = keep.url.appendingPathComponent("staged-\(UUID().uuidString).simwalk")
            try FileManager.default.copyItem(at: url, to: staged)
            return staged
        }
    }

    @Test(arguments: [
        #"{"name":"w","appBundleID":"x.y","setup":{"statusBar":"clean"},"screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#,
        #"{"name":"w","appBundleID":"x.y","setup":{"privacy":{"grant":["location"]}},"screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#,
        #"{"name":"w","appBundleID":"x.y","screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light","locale":"en_GB"}]}]}"#,
        #"{"name":"w","appBundleID":"x.y","screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light","location":{"latitude":1.5,"longitude":2.5}}]}]}"#,
        #"{"name":"w","appBundleID":"x.y","screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light","resetPermissions":["location"]}]}]}"#,
    ])
    func anUnsupportedFeatureRefusesWithoutASingleShellCall(_ walkbook: String) throws {
        let fixture = try Fixture(walkbook: walkbook)
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("simctl"))
        #expect(phone.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    /// A walkbook refusal names the file absolutely, not as typed (SimWalk#117): the reader may not be where the walk was run from.
    @Test
    func aRelativeWalkbookPathIsNamedAbsolutelyInTheRefusal() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        let typed = "no-such-dir/missing.walkbook.json"
        let command = try DeviceWalkCommand.parse([typed, "--udid", Self.udid, "--team", "TEAM", "--output", fixture.output])

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try command.answer(shell: phone.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: fixture.leases, holderPID: fixture.holderPID, now: Date())
        })

        let absolute = URL(fileURLWithPath: typed).standardizedFileURL.path

        #expect(absolute.hasPrefix("/"))
        #expect(thrown.description.contains(absolute))
        #expect(phone.calls.isEmpty)
    }

    @Test
    func aLockedPhoneRefusesBeforeAnyBuild() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.locked = true

        #expect(throws: PhysicalDeviceError.self) { try fixture.answer(phone) }

        #expect(!phone.calls.contains { $0.executable.hasSuffix("xcodebuild") })
    }

    @Test
    func theHappyPathRunsInOrderAndReadsTheNonceBack() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let answer = try fixture.answer(phone)

        #expect(phone.summary == ["list", "lockState", "appearance", "xcodebuild build-for-testing", "xcodebuild test-without-building", "copy", "wipe", "appearance"])
        let build = try #require(phone.calls.first { $0.arguments.contains("build-for-testing") })
        #expect(build.arguments.contains("DEVELOPMENT_TEAM=TEAM"))
        #expect(build.arguments.contains { $0.contains("platform=iOS,id=\(Self.udid)") })
        let walk = try #require(phone.calls.first { $0.arguments.contains("test-without-building") })
        #expect(walk.environment["TEST_RUNNER_SIMWALK_BUILD_HASH"] == "device-unread")
        #expect(walk.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "light")
        let copy = try #require(phone.calls.first { $0.arguments.contains("copy") })
        #expect(copy.arguments.contains("\(RunnerInvocation.deviceContainerBundleID(runnerBundleID: nil))"))
        #expect(copy.arguments.contains("Documents/SimWalkOut/out.simwalk"))
        #expect(copy.arguments.contains { $0.hasSuffix("xctrunner") })
        #expect(answer.verdict == .unqualified("1 of 1 screens captured · 1 capture"))
        #expect(answer.residue.contains("build: not read back on a device (SimWalk#116)"))
        #expect(answer.residue.contains("appearance handed back: light (read back)"))
        #expect(answer.residue.contains { $0.contains("Test Phone · iPhone 17 · iOS 27.0 · \(Self.udid)") })
        #expect(FileManager.default.fileExists(atPath: fixture.output))
    }

    /// An `--output` named without the bundle suffix gets one, and the answer says so (SimWalk#118).
    @Test
    func anOutputWithoutTheSuffixGetsOneAndTheAnswerSaysSo() throws {
        let fixture = try Fixture(outputName: "out")
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let answer = try fixture.answer(phone)

        #expect(FileManager.default.fileExists(atPath: fixture.output + ".simwalk"))
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
        #expect(answer.header.contains("(suffix added)"))
    }

    @Test
    func aBundleCarryingAnotherNonceIsRefused() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], nonceOverride: "someone-else", keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("nonce"))
        #expect(thrown.description.contains("appearance handed back: light (read back)"))
        // The simulator walk logs the same refusal `.runnerFailed` (`WalkCommand.Refusal`), since the runner, not the caller's argument, produced the wrong bundle (SimWalk#117).
        #expect(UsageFailureKind.of(thrown) == .runnerFailed)
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
        let directory = URL(fileURLWithPath: fixture.output).deletingLastPathComponent().path
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.contains(".partial-") }.isEmpty)
    }

    /// A runner failure never excuses a bundle that is not this walk's: the refusal names both, and nothing is left at the output.
    @Test
    func aRunnerFailureDoesNotExcuseAnotherWalksBundle() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], nonceOverride: "someone-else", keep: keep)
        phone.walkStatus = 65

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("nonce"))
        #expect(thrown.description.contains("runner failure:"))
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    /// xcodebuild exits 65 after an XCTest issue yet the runner finalised a complete bundle: the bundle is kept, the answer names the failure, and a phone left in Dark Mode is handed back.
    @Test
    func aRunnerFailureThatLeftThisWalksBundleIsKeptQualifiedAndTheAppearanceHandedBack() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.walkStatus = 65
        phone.setSticks = true
        // The runner leaves a result bundle on disk, so a diagnosis that read it would run xcresulttool.
        var resultBundle: String?
        defer { resultBundle.map { try? FileManager.default.removeItem(atPath: $0) } }
        phone.onCall = { call in
            guard call.arguments.contains("test-without-building"),
                  let flag = call.arguments.firstIndex(of: "-resultBundlePath"), flag + 1 < call.arguments.count else { return }
            resultBundle = call.arguments[flag + 1]
            try? FileManager.default.createDirectory(atPath: call.arguments[flag + 1], withIntermediateDirectories: true)
        }

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains("a runner failure this bundle survived"))
        #expect(answer.residue.contains { $0.hasPrefix("runner failure:") })
        // The result bundle is read only when the runner's failure is the refusal (as the simulator walk does), never for an answer.
        #expect(resultBundle != nil)
        #expect(!phone.calls.contains { $0.arguments.contains("xcresulttool") })
        #expect(answer.residue.contains("appearance handed back by devicectl: found light, was dark, now light (read back)"))
        let set = try #require(phone.calls.first { $0.arguments.contains("settings") })
        #expect(Self.mode(of: set) == "light")
        #expect(FileManager.default.fileExists(atPath: fixture.output))
    }

    /// The runner failed and the copy failed too: the refusal names both, and still says what became of the phone's appearance.
    @Test
    func aRunnerFailureWithNoBundleRefusesNamingBothAndTheHandback() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.walkStatus = 65
        phone.copyStatus = 1
        phone.setSticks = true

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("runner failure:"))
        // The runner's own failure is followed by the diagnosis of its result bundle (SimWalk#124); this runner wrote none.
        #expect(thrown.description.contains("the runner wrote no result bundle"))
        #expect(thrown.description.contains("bundle:"))
        #expect(thrown.description.contains("appearance handed back by devicectl: found light, was dark, now light (read back)"))
        #expect(phone.calls.contains { $0.arguments.contains("settings") && Self.mode(of: $0) == "light" })
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    /// A handback that does not stick is said so, not assumed.
    @Test
    func aHandbackThatDoesNotStickIsRefusedAsNotHandedBack() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.copyStatus = 1

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("appearance NOT handed back: found light, now dark"))
    }

    @Test
    func anAppearanceNotHandedBackQualifiesTheVerdictNamingFoundAndNow() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains("the device's appearance was not handed back: found light, now dark"))
    }

    /// When the re-read after the set fails, the line and the qualification say so, not the stale value read before the set (SimWalk#117).
    @Test
    func aReReadThatFailsAfterTheSetIsNotReportedAsTheStaleNow() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.readsFailAfterSet = true

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains { $0.hasPrefix("the device's appearance could not be read back after setting it, so it may not be as it was found (light)") })
        #expect(answer.residue.contains { $0.hasPrefix("appearance NOT confirmed: found light, was dark, set by devicectl, and the re-read failed:") })
        #expect(!answer.residue.contains { $0.contains("now dark") })
    }

    /// A re-read that fails cannot confirm the text size either: a size the walk changed is still reported (SimWalk#122).
    @Test
    func aReReadThatFailsStillReportsATextSizeTheWalkChanged() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark", textSize: "Extra Large")], keep: keep)
        phone.readsFailAfterSet = true

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains { $0.contains("text size could not be confirmed after the walk: found Large, was Extra Large") })
        #expect(answer.residue.contains { $0.hasPrefix("text size NOT confirmed: found Large, was Extra Large") })
    }

    /// A refusal after `.simwalk` was added to `--output` names the path as the success answer does (SimWalk#122).
    @Test
    func aRefusalNamesTheOutputWithTheSuffixAddedNote() throws {
        let fixture = try Fixture(outputName: "out")
        let keep = try TemporaryDirectory()
        let occupied = URL(fileURLWithPath: fixture.output + ".simwalk")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try Data().write(to: occupied.appendingPathComponent("stale"))
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("\(occupied.standardizedFileURL.path) (suffix added)"))
    }

    /// A set that failed and a re-read that then failed must not claim a set was made.
    @Test
    func aSetThatFailedAndAReReadThatFailedDoesNotClaimTheSet() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.setFails = true
        phone.readsFailAfterSet = true

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains { $0.hasPrefix("the device's appearance could not be set back or read back, so it may not be as it was found (light)") })
        #expect(answer.residue.contains { $0.hasPrefix("appearance NOT confirmed: found light, was dark, set NOT made (devicectl:") && $0.contains("and the re-read failed:") })
        #expect(!answer.residue.contains { $0.contains("set by devicectl") })
    }

    @Test
    func aTextSizeNotHandedBackQualifiesTheVerdictToo() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light", textSize: "Large"), Self.appearance("light", textSize: "XL")], keep: keep)

        let answer = try fixture.answer(phone)

        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }

        #expect(qualifications.contains("the device's text size was not handed back: found Large, now XL"))
    }
}

extension DeviceWalkCommandTests {
    /// Answers `devicectl` and `xcodebuild`, recording every call; `copied` is what the copy writes into its destination.
    struct Call {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
    }

    final class Phone {
        var calls: [Call] = []
        var appearances: [String]
        var locked = false
        /// The exit status `xcodebuild test-without-building` answers with.
        var walkStatus: Int32 = 0
        /// The exit status `devicectl device copy from` answers with; non-zero copies nothing.
        var copyStatus: Int32 = 0
        /// The exit status `devicectl device copy to` (the container wipe) answers with.
        var wipeStatus: Int32 = 0
        /// Whether `devicectl device settings appearance --mode <m>` takes effect on later reads.
        var setSticks = false
        /// Whether `devicectl device info appearance` fails once a `settings appearance` set has been made, as a phone that drops off after the set would.
        var readsFailAfterSet = false
        /// Whether `devicectl device settings appearance --mode <m>` itself fails.
        var setFails = false
        private var hasSet = false
        /// Whether Increase Contrast is on, as `device info appearance` reads it.
        var contrast = false
        /// Whether `devicectl device settings appearance --increase-contrast` takes effect on later reads.
        var contrastSticks = true
        /// The exit status `devicectl device install app` answers with; non-zero answers `installError` on stderr.
        var installStatus: Int32 = 0
        var installError = ""
        /// Writes the bundle the phone "holds", given the nonce, build hash and provenance the runner was passed.
        var bundleFor: (String?, String, String?) throws -> URL
        /// Runs as each command is recorded, before it answers: lets a test change the world at a named step.
        var onCall: (Call) -> Void = { _ in }
        /// Runs when `xcodebuild test-without-building` is called: the walk itself.
        var duringWalk: () -> Void = {}
        /// The exit status `xcodebuild build-for-testing` answers with.
        var buildStatus: Int32 = 0
        /// Answers a call before any of the above, once it is recorded; `nil` leaves it to them (a measure run and its `xcresulttool` read, SimWalk#67).
        var answering: (Call) throws -> Shell.Result? = { _ in nil }

        init(appearances: [String], bundleFor: @escaping (String?, String, String?) throws -> URL) {
            self.appearances = appearances
            self.bundleFor = bundleFor
        }

        var shell: Shell {
            Shell(script: { executable, arguments, environment in
                let call = Call(executable: executable, arguments: arguments, environment: environment)
                self.calls.append(call)
                self.onCall(call)
                if let answer = try self.answering(call) {
                    return answer
                }
                func ok(_ out: String = "") -> Shell.Result {
                    Shell.Result(status: 0, standardOutput: out, standardError: "")
                }
                if arguments.starts(with: ["devicectl", "device", "install", "app"]), self.installStatus != 0 {
                    return Shell.Result(status: self.installStatus, standardOutput: "", standardError: self.installError)
                }
                if arguments.contains("lockState") {
                    return ok(#"{"result":{"passcodeRequired":\#(self.locked)}}"#)
                }
                if arguments.contains("settings"), let flag = arguments.firstIndex(of: "--increase-contrast") {
                    if self.contrastSticks {
                        self.contrast = arguments[flag + 1] == "on"
                    }
                    return ok()
                }
                if arguments.contains("settings"), let flag = arguments.firstIndex(of: "--mode") {
                    self.hasSet = true
                    if self.setFails {
                        return Shell.Result(status: 1, standardOutput: "", standardError: "set refused")
                    }
                    if self.setSticks {
                        self.appearances = [DeviceWalkCommandTests.appearance(arguments[flag + 1])]
                    }
                    return ok()
                }
                if arguments.contains("build-for-testing"), self.buildStatus != 0 {
                    return Shell.Result(status: self.buildStatus, standardOutput: "", standardError: "** BUILD FAILED **")
                }
                if arguments.contains("test-without-building") {
                    self.duringWalk()
                }
                if arguments.contains("test-without-building"), self.walkStatus != 0 {
                    return Shell.Result(status: self.walkStatus, standardOutput: "", standardError: "** TEST FAILED **")
                }
                if arguments.contains("appearance"), self.readsFailAfterSet, self.hasSet {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "device went away")
                }
                if arguments.contains("appearance") {
                    let reply = self.appearances.count > 1 ? self.appearances.removeFirst() : self.appearances[0]
                    return ok(reply.replacingOccurrences(of: #""increaseContrast":false"#, with: #""increaseContrast":\#(self.contrast)"#))
                }
                if arguments.starts(with: ["devicectl", "list", "devices"]) {
                    return ok(DeviceWalkCommandTests.list)
                }
                if arguments.starts(with: ["devicectl", "device", "copy", "to"]), self.wipeStatus != 0 {
                    return Shell.Result(status: self.wipeStatus, standardOutput: "", standardError: "container unavailable")
                }
                if arguments.starts(with: ["devicectl", "device", "copy", "from"]) {
                    if self.copyStatus != 0 {
                        return Shell.Result(status: self.copyStatus, standardOutput: "", standardError: "copy failed")
                    }
                    guard let flag = arguments.firstIndex(of: "--destination") else { return ok() }
                    let destination = URL(fileURLWithPath: arguments[flag + 1])
                    let nonce = self.calls.last { $0.arguments.contains("test-without-building") }?.environment["TEST_RUNNER_SIMWALK_NONCE"]
                    let buildHash = self.calls.last { $0.arguments.contains("test-without-building") }?.environment["TEST_RUNNER_SIMWALK_BUILD_HASH"] ?? AppBuildIdentity.unreadOnDevice
                    let provenance = self.calls.last { $0.arguments.contains("test-without-building") }?.environment["TEST_RUNNER_SIMWALK_BUILD_PROVENANCE"]
                    let bundle = try self.bundleFor(nonce, buildHash, provenance)
                    try FileManager.default.copyItem(at: bundle, to: destination)
                }
                return ok()
            })
        }

        /// The commands in order, each reduced to what names it.
        var summary: [String] {
            calls.map { call in
                if call.executable.hasSuffix("xcodebuild") {
                    return call.arguments.contains("build-for-testing") ? "xcodebuild build-for-testing" : "xcodebuild test-without-building"
                }
                if call.arguments.starts(with: ["devicectl", "device", "copy", "to"]) {
                    return "wipe"
                }
                if let flag = call.arguments.firstIndex(of: "--increase-contrast") {
                    return "contrast \(call.arguments[flag + 1])"
                }
                return call.arguments.filter { ["list", "lockState", "appearance", "install", "copy"].contains($0) }.joined(separator: " ")
            }
        }
    }

    struct Fixture {
        let directory: TemporaryDirectory
        let walkbookPath: String
        let output: String
        let builds: RunnerBuilds
        /// A scratch lease store: a test never touches `~/.simwalk/leases`.
        let leases: LeaseStore
        let holderPID: Int32 = 4242

        init(walkbook: String = DeviceWalkCommandTests.plainWalkbook, outputName: String = "out.simwalk") throws {
            directory = try TemporaryDirectory()
            walkbookPath = directory.url.appendingPathComponent("w.walkbook.json").path
            try walkbook.write(toFile: walkbookPath, atomically: true, encoding: .utf8)
            output = directory.url.appendingPathComponent(outputName).path
            builds = RunnerBuilds(directory: directory.url.appendingPathComponent("builds"))
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases"), isAlive: { _ in true })
        }

        func command(_ device: [String] = ["--udid", DeviceWalkCommandTests.udid]) throws -> DeviceWalkCommand {
            try DeviceWalkCommand.parse([walkbookPath] + device + ["--team", "TEAM", "--output", output])
        }

        func source() -> () throws -> RunnerSource {
            let project = directory.url.appendingPathComponent("Runner").path
            return { RunnerSource(projectPath: project, commit: "abc1234", origin: .override) }
        }

        /// A fake `.app` in this fixture's directory: an `Info.plist` naming `bundleID` and an executable of `bytes`; `plist: false` leaves it without one.
        func fakeApp(bundleID: String = "x.y", bytes: String = "binary", plist: Bool = true) throws -> String {
            let app = directory.url.appendingPathComponent("Fake-\(UUID().uuidString).app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try bytes.write(to: app.appendingPathComponent("Fake"), atomically: true, encoding: .utf8)
            if plist {
                let info: [String: Any] = ["CFBundleExecutable": "Fake", "CFBundleIdentifier": bundleID]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
            }
            return app.path
        }

        func answer(_ phone: Phone, device: [String] = ["--udid", DeviceWalkCommandTests.udid], extra: [String] = []) throws -> Answer {
            try command(device + extra).answer(shell: phone.shell, builds: builds, resolveRunner: source(), leases: leases, holderPID: holderPID, now: Date())
        }
    }
}

/// The phone's lease (SimWalk#116): taken before any `devicectl` call, a token's walk renews and leaves it, an implicit one is released on every exit.
extension DeviceWalkCommandTests {
    private func leasedPhone(_ keep: TemporaryDirectory) -> Phone {
        phone(appearances: [Self.appearance("light")], keep: keep)
    }

    static var contrastWalkbook: String {
        #"{"name":"w","appBundleID":"x.y","setup":{"increaseContrast":true},"screens":[{"id":"today","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
    }

    /// `setup.increaseContrast` on a device (SimWalk#116, ruling 6): read with the appearance, set, read back, then the runner; handed back on the way out and recorded in the manifest.
    @Test
    func increaseContrastIsSetReadBackBeforeTheRunnerAndHandedBackWithTheValueFound() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let answer = try fixture.answer(phone)

        #expect(phone.summary == ["list", "lockState", "appearance", "contrast on", "appearance", "xcodebuild build-for-testing", "xcodebuild test-without-building", "copy", "wipe", "appearance", "contrast off", "appearance"])
        #expect(!phone.contrast)
        #expect(answer.residue.contains("Increase Contrast handed back: off (read back)"))
        #expect(answer.verdict == .unqualified("1 of 1 screens captured · 1 capture"))
        let record = try #require(try CaptureBundle.read(at: URL(fileURLWithPath: fixture.output)).manifest.deviceSetup)
        #expect(record.made.count == 1 && record.made[0].contains("Increase Contrast enabled by devicectl, found disabled, read back enabled"))
        #expect(record.handedBack == ["Increase Contrast put back off, read back"])
        #expect(record.notHandedBack.isEmpty)
    }

    @Test
    func increaseContrastFoundOnIsLeftOn() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.contrast = true

        let answer = try fixture.answer(phone)

        #expect(!phone.summary.contains("contrast off"))
        #expect(phone.contrast)
        #expect(answer.residue.contains("Increase Contrast handed back: on (read back)"))
    }

    /// A read-back that disagrees with the set refuses before the runner starts, and the walk still hands back.
    @Test
    func increaseContrastThatReadsBackOffRefusesBeforeTheRunnerAndStillHandsBack() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.contrastSticks = false

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("setup.increaseContrast"))
        #expect(thrown.usageFailureKind == .setupFailed)
        #expect(thrown.description.contains("Increase Contrast handed back: off (read back)"))
        #expect(!phone.calls.contains { $0.executable.hasSuffix("xcodebuild") })
        #expect(phone.summary == ["list", "lockState", "appearance", "contrast on", "appearance", "appearance"])
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    @Test
    func aRunnerFailureStillHandsIncreaseContrastBack() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.walkStatus = 65

        let answer = try fixture.answer(phone)

        #expect(!phone.contrast)
        #expect(phone.summary.suffix(3) == ["appearance", "contrast off", "appearance"])
        #expect(answer.residue.contains("Increase Contrast handed back: off (read back)"))
    }

    @Test
    func theRunnersContainerIsEmptiedAfterTheCopyOnlyAtItsOwnContainer() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let answer = try fixture.answer(phone, extra: ["--runner-bundle-id", "com.team.runner"])

        let wipe = try #require(phone.calls.first { $0.arguments.starts(with: ["devicectl", "device", "copy", "to"]) })
        func value(after flag: String) -> String? {
            wipe.arguments.firstIndex(of: flag).map { wipe.arguments[$0 + 1] }
        }
        #expect(value(after: "--domain-identifier") == "com.team.runner.xctrunner")
        #expect(value(after: "--destination") == "Documents")
        #expect(value(after: "--remove-existing-content") == "true")
        #expect(value(after: "--device") == Self.udid)
        let copyIndex = try #require(phone.summary.firstIndex(of: "copy"))
        #expect(try #require(phone.summary.firstIndex(of: "wipe")) == copyIndex + 1)
        #expect(answer.residue.contains("runner container emptied"))
        #expect(answer.verdict == .unqualified("1 of 1 screens captured · 1 capture"))
    }

    /// The wipe empties the runner's whole container, so it runs only while this walk's token still holds the lease: another holder may have taken the phone during a long walk and its runner be mid-run in that container.
    @Test
    func theContainerIsLeftWhenTheLeaseIsNoLongerThisWalks() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.duringWalk = {
            // The walk's lease lapses and another holder takes the phone while the runner runs.
            for entry in fixture.leases.all() {
                _ = try? fixture.leases.remove(udid: entry.udid, token: entry.lease.token)
            }
            _ = try? fixture.leases.acquire(udid: Self.udid, ttl: 600, holderPID: 9999, now: Date(), physicalDevice: true)
        }

        let answer = try fixture.answer(phone)

        #expect(!phone.summary.contains("wipe"))
        #expect(answer.residue.contains { $0.contains("runner container left as it is: the lease on \(Self.udid) is no longer this walk's") })
        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }
        #expect(qualifications.contains("the runner's container was not emptied"))
    }

    /// One renewal gates the wipe and the handback: a walk whose lease passed to another holder neither empties the container nor flips the appearance or contrast under them, and says why in a line each.
    @Test
    func theHandbackIsSkippedWhenTheLeaseIsNoLongerThisWalks() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        // Dark after the walk, so a handback that ran would set the style back.
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.duringWalk = {
            for entry in fixture.leases.all() {
                _ = try? fixture.leases.remove(udid: entry.udid, token: entry.lease.token)
            }
            _ = try? fixture.leases.acquire(udid: Self.udid, ttl: 600, holderPID: 9999, now: Date(), physicalDevice: true)
        }

        let answer = try fixture.answer(phone)

        let sets = phone.calls.filter { $0.arguments.contains("settings") && !$0.arguments.starts(with: ["devicectl", "device", "copy", "to"]) }
        #expect(sets.map { $0.arguments.contains("--increase-contrast") } == [true])
        #expect(!phone.summary.contains("wipe"))
        #expect(!phone.summary.contains("contrast off"))
        #expect(answer.residue.contains { $0.contains("appearance not handed back: the lease on \(Self.udid) is no longer this walk's") })
        #expect(answer.residue.contains { $0.contains("Increase Contrast not handed back: the lease on \(Self.udid) is no longer this walk's") })
        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }
        #expect(qualifications.contains { $0.contains("appearance was not handed back: the lease on") })
        // The manifest's contrast record says why, not only the answer (SimWalk#127).
        let record = try #require(try CaptureBundle.read(at: URL(fileURLWithPath: fixture.output)).manifest.deviceSetup)
        #expect(record.handedBack.isEmpty)
        #expect(record.notHandedBack.contains { $0.contains("the lease on \(Self.udid) is no longer this walk's") })
    }

    /// A renewal that fails before the walk (not only the one before the wipe) skips the handback too: the phone is the new holder's, so no appearance is read or set after the lease was taken (SimWalk#127).
    @Test
    func aLeaseTakenBeforeTheFirstRenewalHandsNothingBack() throws {
        let fixture = try Fixture(walkbook: Self.contrastWalkbook)
        let keep = try TemporaryDirectory()
        // Dark on any second read, so a handback that ran would set the style back.
        let phone = phone(appearances: [Self.appearance("light"), Self.appearance("dark")], keep: keep)
        phone.onCall = { call in
            guard call.arguments.contains("appearance"), call.arguments.contains("info") else { return }
            for entry in fixture.leases.all() {
                _ = try? fixture.leases.remove(udid: entry.udid, token: entry.lease.token)
            }
            _ = try? fixture.leases.acquire(udid: Self.udid, ttl: 600, holderPID: 9999, now: Date(), physicalDevice: true)
        }

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(phone.summary == ["list", "lockState", "appearance"])
        #expect(thrown.description.contains("appearance not handed back: the lease on \(Self.udid) is no longer this walk's"))
        #expect(thrown.description.contains("Increase Contrast not handed back"))
    }

    @Test
    func theContainerIsEmptiedWhileTheLeaseIsStillThisWalks() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        let answer = try fixture.answer(phone)

        #expect(phone.summary.contains("wipe"))
        #expect(answer.residue.contains("runner container emptied"))
    }

    @Test
    func theContainerIsEmptiedAfterAFailedCopyAndTheRefusalSaysSo() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.copyStatus = 1

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(phone.summary == ["list", "lockState", "appearance", "xcodebuild build-for-testing", "xcodebuild test-without-building", "copy", "wipe", "appearance"])
        #expect(thrown.description.contains("runner container emptied"))
    }

    @Test
    func theContainerIsEmptiedAfterARunnerFailureWithNoBundle() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.walkStatus = 65
        phone.copyStatus = 1

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })
        let walk = try #require(phone.summary.firstIndex(of: "xcodebuild test-without-building"))

        #expect(phone.summary[(walk + 1)...].starts(with: ["copy", "wipe"]))
        #expect(thrown.description.contains("runner container emptied"))
    }

    @Test
    func aRefusalBeforeTheRunnerRanWipesNothing() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.buildStatus = 65

        #expect(throws: (any Error).self) { try fixture.answer(phone) }

        #expect(!phone.summary.contains("wipe"))
    }

    @Test
    func aWipeThatFailsQualifiesAGoodWalkAndDoesNotRefuseIt() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.wipeStatus = 1

        let answer = try fixture.answer(phone)

        #expect(answer.residue.contains("runner container not emptied: container unavailable"))
        guard case let .qualified(reasons, _) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }
        #expect(reasons.contains("the runner's container was not emptied"))
        #expect(FileManager.default.fileExists(atPath: fixture.output))
    }

    @Test
    func aPhoneAnotherLivePidHoldsIsRefusedNamingTheHolderWithNothingRunOnIt() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let theirs = try fixture.leases.acquire(udid: Self.udid, ttl: 600, holderPID: 777, now: Date(), physicalDevice: true)

        let thrown = try #require(#expect(throws: LeaseError.self) { try fixture.answer(phone) })

        #expect(thrown.description.contains("pid 777"))
        #expect(thrown.description.contains(LeaseError.time(theirs.expiresAt)))
        #expect(phone.calls.isEmpty)
        #expect(fixture.leases.entry(token: theirs.token) != nil)
    }

    @Test
    func anImplicitLeaseIsHeldDuringTheWalkAndGoneAfterASuccess() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let during = Observed()
        phone.duringWalk = { during.set(fixture.leases.all()) }

        _ = try fixture.answer(phone)

        let held = try #require(during.entries.first)

        #expect(during.entries.count == 1)
        #expect(held.udid == Self.udid)
        #expect(held.lease.physicalDevice == true)
        #expect(held.lease.holderPID == fixture.holderPID)
        #expect(fixture.leases.all().isEmpty)
    }

    @Test
    func anImplicitLeaseIsGoneAfterARefusal() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        phone.locked = true

        #expect(throws: (any Error).self) { try fixture.answer(phone) }

        #expect(!phone.calls.isEmpty)
        #expect(fixture.leases.all().isEmpty)
    }

    @Test
    func aTokenWalksRenewsAndLeavesTheLeaseToItsHolder() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let start = Date().addingTimeInterval(-60)
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 300, holderPID: 99, now: start, physicalDevice: true)

        _ = try fixture.answer(phone, device: ["--lease", lease.token])

        let after = try #require(fixture.leases.entry(token: lease.token))

        #expect(after.lease.expiresAt > lease.expiresAt)
        #expect(after.udid == Self.udid)
        #expect(phone.calls.contains { $0.arguments.contains("test-without-building") })
    }

    /// SimWalk#128: a device walk's claim is taken before its first `devicectl` call, so a session end racing the setup already sees it.
    @Test
    func aDeviceWalkTakesItsClaimBeforeTheFirstDevicectlCall() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let atFirstCall = Observed()
        var seenFirst = false
        phone.onCall = { _ in
            guard !seenFirst else { return }
            seenFirst = true
            atFirstCall.setWalked(WalkClaim.walkedDevices(in: fixture.leases, isAlive: HolderProcess.isAlive))
        }

        _ = try fixture.answer(phone)

        #expect(seenFirst)
        #expect(atFirstCall.walked == [Self.udid])
    }

    /// SimWalk#128: a walk takes a claim on the phone whatever lease it runs under, and leaves none behind.
    @Test
    func aTokenWalkHoldsAClaimDuringTheWalkAndNoneAfter() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let during = Observed()
        phone.duringWalk = { during.setWalked(WalkClaim.walkedDevices(in: fixture.leases, isAlive: HolderProcess.isAlive)) }
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 300, holderPID: 99, now: Date(), physicalDevice: true)

        _ = try fixture.answer(phone, device: ["--lease", lease.token])

        #expect(during.walked == [Self.udid])
        #expect(WalkClaim.walkedDevices(in: fixture.leases, isAlive: HolderProcess.isAlive).isEmpty)
        #expect(fixture.leases.entry(token: lease.token) != nil)
    }

    @Test
    func aRefusedWalkLeavesNoClaim() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        phone.locked = true

        #expect(throws: (any Error).self) { try fixture.answer(phone) }

        #expect(!phone.calls.isEmpty)
        #expect(WalkClaim.walkedDevices(in: fixture.leases, isAlive: HolderProcess.isAlive).isEmpty)
    }

    @Test
    func aTokenOnASimulatorIsRefusedWithNothingRun() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = leasedPhone(keep)
        let lease = try fixture.leases.acquire(udid: "SIM-1", ttl: 300, holderPID: 99, now: Date())

        let thrown = try #require(#expect(throws: LeaseError.self) { try fixture.answer(phone, device: ["--lease", lease.token]) })

        #expect(thrown == .notPhysicalLease(udid: "SIM-1"))
        #expect(phone.calls.isEmpty)
        #expect(fixture.leases.entry(token: lease.token) != nil)
    }

    @Test
    func aTokenThatHoldsNothingIsRefusedWithNothingRun() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())

        #expect(throws: LeaseError.noSuchLease) { try fixture.answer(phone, device: ["--lease", "nope"]) }

        #expect(phone.calls.isEmpty)
    }

    @Test
    func udidWithLeaseAndNeitherAreValidationErrors() throws {
        let fixture = try Fixture()

        #expect(throws: (any Error).self) { try fixture.command(["--udid", Self.udid, "--lease", "t"]) }
        #expect(throws: (any Error).self) { try fixture.command([]) }
    }

    /// The lease entries a walk saw while it ran.
    final class Observed: @unchecked Sendable {
        private(set) var entries: [LeaseStore.Entry] = []
        private(set) var walked: Set<String> = []

        func setWalked(_ walked: Set<String>) {
            self.walked = walked
        }

        func set(_ entries: [LeaseStore.Entry]) {
            self.entries = entries
        }
    }
}

/// `--app` (SimWalk#116): the app is checked before the lease, installed after the prerequisites and before the runner build, and its Mac-side hash is what the walk records.
extension DeviceWalkCommandTests {
    @Test
    func anInstalledAppIsHashedOnTheMacInstalledBeforeTheBuildAndRecordedAsInstalled() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        let app = try fixture.fakeApp()
        let hash = try AppBuildIdentity.hash(ofAppAt: app)

        let answer = try fixture.answer(phone, extra: ["--app", app])

        #expect(phone.summary == ["list", "lockState", "appearance", "install", "xcodebuild build-for-testing", "xcodebuild test-without-building", "copy", "wipe", "appearance"])
        let install = try #require(phone.calls.first { $0.arguments.contains("install") })
        #expect(install.arguments.suffix(3) == ["--device", Self.udid, app])
        let walk = try #require(phone.calls.first { $0.arguments.contains("test-without-building") })
        #expect(walk.environment["TEST_RUNNER_SIMWALK_BUILD_HASH"] == hash)
        #expect(walk.environment["TEST_RUNNER_SIMWALK_BUILD_PROVENANCE"] == "installed")
        #expect(answer.residue.contains("build: \(AppBuildIdentity.printed(hash)) (installed by this walk, not read back)"))
        #expect(answer.residue.contains("the phone's previous copy of x.y, if any, was replaced and not restored"))
    }

    @Test
    func aWalkWithoutAppSendsNoProvenance() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)

        _ = try fixture.answer(phone)

        let walk = try #require(phone.calls.first { $0.arguments.contains("test-without-building") })

        #expect(walk.environment["TEST_RUNNER_SIMWALK_BUILD_PROVENANCE"] == nil)
    }

    @Test
    func anAppOfAnotherBundleIDIsRefusedBeforeTheLeaseWithNothingRun() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        let app = try fixture.fakeApp(bundleID: "other.app")

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", app]) })

        #expect(thrown.description.contains("other.app"))
        #expect(phone.calls.isEmpty)
        #expect(fixture.leases.all().isEmpty)
    }

    @Test
    func anUnreadableAppIsRefusedWithNothingRun() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        let app = try fixture.fakeApp(plist: false)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", app]) })

        #expect(thrown.description.contains("not an app bundle"))
        #expect(phone.calls.isEmpty)
        #expect(fixture.leases.all().isEmpty)
    }

    @Test
    func aFailedInstallRefusesNamingDevicectlsErrorAndBuildsNothing() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], keep: keep)
        phone.installStatus = 1
        phone.installError = "ERROR: The provisioning profile does not include this device"

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", fixture.fakeApp()]) })

        #expect(thrown.description.contains("The provisioning profile does not include this device"))
        #expect(thrown.description.contains("appearance handed back: light (read back)"))
        #expect(!phone.calls.contains { $0.executable.hasSuffix("xcodebuild") })
        #expect(fixture.leases.all().isEmpty)
    }
}

/// The renewals and the install (SimWalk#116 review): a lease that cannot be renewed refuses before anything changes on the phone, and every refusal after the install says the app was replaced.
extension DeviceWalkCommandTests {
    private static var replaced: String {
        "the phone's previous copy of x.y, if any, was replaced and not restored"
    }

    @Test
    func anExpiredTokenOrAHolderGoneIsRefusedWithNothingRun() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        let dead = LeaseStore(directory: fixture.directory.url.appendingPathComponent("dead-leases"), isAlive: { _ in false })
        let lease = try dead.acquire(udid: Self.udid, ttl: 300, holderPID: 99, now: Date(), physicalDevice: true)
        let command = try fixture.command(["--lease", lease.token])

        #expect(throws: LeaseError.self) {
            try command.answer(shell: phone.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: dead, holderPID: fixture.holderPID, now: Date())
        }

        #expect(phone.calls.isEmpty)
    }

    @Test
    func aLeaseThatLapsesDuringTheAppearanceReadIsRefusedBeforeTheInstallAndTheBuild() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 300, holderPID: 99, now: Date(), physicalDevice: true)
        phone.onCall = { call in
            if call.arguments.contains("appearance") {
                _ = try? fixture.leases.remove(udid: Self.udid, token: lease.token)
            }
        }

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, device: ["--lease", lease.token], extra: ["--app", fixture.fakeApp()]) })

        #expect(thrown.description.contains("no lease carries that token"))
        #expect(!phone.calls.contains { $0.arguments.contains("install") })
        #expect(!phone.calls.contains { $0.arguments.contains("build-for-testing") })
    }

    @Test
    func aLeaseThatLapsesDuringTheBuildIsRefusedBeforeTheRunner() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 300, holderPID: 99, now: Date(), physicalDevice: true)
        phone.onCall = { call in
            if call.arguments.contains("build-for-testing") {
                _ = try? fixture.leases.remove(udid: Self.udid, token: lease.token)
            }
        }

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, device: ["--lease", lease.token]) })

        #expect(thrown.description.contains("no lease carries that token"))
        #expect(phone.calls.contains { $0.arguments.contains("build-for-testing") })
        #expect(!phone.calls.contains { $0.arguments.contains("test-without-building") })
    }

    @Test
    func aBuildFailureAfterTheInstallSaysTheAppWasReplaced() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        phone.buildStatus = 65
        let app = try fixture.fakeApp()
        let hash = try AppBuildIdentity.hash(ofAppAt: app)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", app]) })

        #expect(thrown.description.contains(Self.replaced))
        #expect(thrown.description.contains(AppBuildIdentity.printed(hash)))
        #expect(thrown.description.contains("appearance handed back: light (read back)"))
    }

    @Test
    func aNonceRefusalAfterTheInstallSaysTheAppWasReplacedAndNothingWasWritten() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], nonceOverride: "someone-else", keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", fixture.fakeApp()]) })

        #expect(thrown.description.contains(Self.replaced))
        #expect(thrown.description.contains("refused and not written"))
        #expect(!thrown.description.contains("bundle at"))
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    @Test
    func aWalkWithoutAnInstallNeverClaimsAReplacement() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        phone.buildStatus = 65

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone) })

        #expect(!thrown.description.contains("replaced"))
    }

    @Test
    func aRunnerThatDropsTheProvenanceOfAnInstalledBuildIsRefusedAndNothingIsWritten() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let phone = phone(appearances: [Self.appearance("light")], dropsProvenance: true, keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", fixture.fakeApp()]) })

        #expect(thrown.description.contains("provenance"))
        #expect(!FileManager.default.fileExists(atPath: fixture.output))
    }

    @Test
    func anAppRebuiltBetweenTheCheckAndTheInstallIsRefusedBeforeTheBuild() throws {
        let fixture = try Fixture()
        let phone = try leasedPhone(TemporaryDirectory())
        let app = try fixture.fakeApp()
        phone.onCall = { call in
            if call.arguments.contains("install") {
                try? "rebuilt".write(to: URL(fileURLWithPath: app).appendingPathComponent("Fake"), atomically: true, encoding: .utf8)
            }
        }

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, extra: ["--app", app]) })

        #expect(thrown.description.contains("not the one checked"))
        #expect(thrown.description.contains("build installed by this walk: unknown"))
        #expect(!thrown.description.contains("hashed on this Mac before the lease"))
        #expect(thrown.description.contains(Self.replaced))
        #expect(!phone.calls.contains { $0.arguments.contains("build-for-testing") })
    }
}
