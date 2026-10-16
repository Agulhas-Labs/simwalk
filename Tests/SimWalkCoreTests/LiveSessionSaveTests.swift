//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `session save` against a channel of scripted responses: the screen it builds, what it refuses, and that what it writes loads.
struct LiveSessionSaveTests {
    @Test
    func saveBuildsTheScreenFromTheLaunchStateAndTheLandedRouteWithoutTheOwner() throws {
        let fixture = try Fixture(state: Walkbook.CaptureState(theme: .dark, locale: "en_GB"))
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")

        let answer = try LiveSessionSave(screenID: "detail-live", expect: "route-detail", since: nil)
            .perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        let saved = try WalkbookLoader.load(contentsOf: into)

        #expect(saved.name == "detail-live")
        #expect(saved.appBundleID == "dev.simwalk.route-fixture")
        #expect(saved.screens == [Walkbook.Screen(
            id: "detail-live",
            route: [.systemTap(label: "Allow"), .openURL(url: "simwalk-fixture://detail")],
            states: [Walkbook.CaptureState(theme: .dark, locale: "en_GB")],
            expect: "route-detail"
        )])
        #expect(try !String(contentsOf: into, encoding: .utf8).contains("owner"))
        #expect(answer.residue.contains("from requests: 1, 3 — every step that landed since launch; a walk takes it from launch"))
        #expect(answer.residue.last == "replay it: simwalk walk \(into.path.tildedPath) --screens detail-live --output <new bundle>.simwalk")
    }

    @Test
    func aSessionLaunchedPlainIsSavedInTheAppearanceTheDeviceWasFoundIn() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")

        _ = try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        #expect(try WalkbookLoader.load(contentsOf: into).screens.first?.states == [Walkbook.CaptureState(theme: .light)])
    }

    @Test
    func saveRefusesAnExistingScreenIDAndADifferentAppLeavingTheFileAlone() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")
        let save = LiveSessionSave(screenID: "detail-live", expect: nil, since: nil)
        _ = try save.perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)
        let before = try Data(contentsOf: into)

        #expect(throws: LiveSessionSaveError.screenExists(path: into.path, id: "detail-live")) {
            try save.perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)
        }

        let other = fixture.directory.url.appendingPathComponent("other.json")
        let foreign = Walkbook(name: "other", appBundleID: "com.example.other", screens: [Walkbook.Screen(id: "home", route: [.back], states: [Walkbook.CaptureState(theme: .light)])])
        try JSONEncoder().encode(foreign).write(to: other)

        #expect(throws: LiveSessionSaveError.differentApp(path: other.path, walkbook: "com.example.other", session: "dev.simwalk.route-fixture")) {
            try save.perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: other)
        }
        #expect(try Data(contentsOf: into) == before)
    }

    @Test
    func aSecondScreenIsAppendedAndTheFileStillValidates() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")
        _ = try LiveSessionSave(screenID: "first", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        let answer = try LiveSessionSave(screenID: "second", expect: nil, since: 3).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        let saved = try WalkbookLoader.load(contentsOf: into)

        #expect(saved.screens.map(\.id) == ["first", "second"])
        #expect(WalkbookLoader.problems(in: saved).isEmpty)
        #expect(answer.residue.contains { $0.hasPrefix("re-encoded: ") })
    }

    @Test
    func sinceSlicesTheRouteFromThatRequestOn() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")

        _ = try LiveSessionSave(screenID: "detail-live", expect: nil, since: 2).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        #expect(try fixture.channel.landedSteps(since: 2).map(\.request) == [3])
        #expect(try WalkbookLoader.load(contentsOf: into).screens.first?.route == [.openURL(url: "simwalk-fixture://detail")])
        #expect(throws: LiveSessionSaveError.nothingLanded(since: 4)) {
            try LiveSessionSave(screenID: "late", expect: nil, since: 4).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)
        }
    }

    /// A device session whose host filed requests 1 and 3 but never 2 — the runner served it, the host never filed it — is refused by number rather than saved as the route 1, 3; a range from after the gap saves.
    @Test
    func aDeviceSessionWithAGapInItsNumberingIsRefusedNamingTheMissingRequest() throws {
        let directory = try TemporaryDirectory()
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
        try channel.prepare()
        try channel.writeLaunch(LiveSessionLaunch(appBundleID: "dev.simwalk.route-fixture", state: Walkbook.CaptureState(theme: .light)))
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "RouteFixture")
        let delta = ScreenDelta(from: tree, to: tree)
        for (number, label) in [(1, "First"), (3, "Third"), (4, "Fourth")] {
            try channel.file(DeviceSessionRequest(action: .step, step: .tap(label: label)), answeredBy: LiveSessionResponse(n: number, action: .step, step: .landed(.tap(label: label), delta: delta)))
        }
        let into = directory.url.appendingPathComponent("live.walkbook.json")

        #expect(throws: LiveSessionSaveError.unfiledRequests([2])) {
            try LiveSessionSave(screenID: "gapped", expect: nil, since: nil).perform(sessionID: "s1", channel: channel, foundAppearance: nil, into: into)
        }
        #expect(!FileManager.default.fileExists(atPath: into.path))
        #expect("\(LiveSessionSaveError.unfiledRequests([2]))".hasPrefix("request 2 was answered by the runner but never filed on this Mac, so the route may lack a step — save from after it with --since 3"))
        _ = try LiveSessionSave(screenID: "after", expect: nil, since: 3).perform(sessionID: "s1", channel: channel, foundAppearance: nil, into: into)
        #expect(try WalkbookLoader.load(contentsOf: into).screens.first?.route == [.tap(label: "Third"), .tap(label: "Fourth")])
    }

    /// A step taken that did not land is left out of the saved route, and the save says so by request, since what it did to the app is not replayed.
    @Test
    func aSaveNamesTheStepsThatActedWithoutLanding() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")

        let answer = try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)

        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.verdict.line.contains("request 4: tap 'Nowhere' was taken and did not land, so it is not in the saved route — if it changed the app, a replay may drift"))
    }

    @Test
    func aStateTheLoaderRefusesIsNeverWritten() throws {
        let fixture = try Fixture(state: Walkbook.CaptureState(theme: .light, dynamicTypeSize: "huge"))
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")

        #expect(throws: WalkbookLoadError.self) {
            try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)
        }
        #expect(!FileManager.default.fileExists(atPath: into.path))
    }

    /// A walkbook in a directory that does not exist is refused as not writable, naming the walkbook — not the lock file beside it that could not be made first.
    @Test
    func aWalkbookInAMissingDirectoryIsRefusedByItsOwnPath() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("missing", isDirectory: true).appendingPathComponent("live.walkbook.json")

        let error = #expect(throws: LiveSessionSaveError.self) {
            try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: into)
        }
        let refused: String? = if case let .notWritable(path, _) = error {
            path
        } else {
            nil
        }

        #expect(refused == into.path)
    }

    /// Saves into one walkbook at the same moment all land: each loads, appends and writes under the walkbook's lock, so none writes back a walkbook that has lost another's screen.
    @Test
    func concurrentSavesIntoOneWalkbookLoseNoScreen() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")
        let channel = fixture.channel
        let ids = (1 ... 32).map { "screen-\($0)" }
        let failures = OSAllocatedUnfairLock(initialState: [String]())

        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            do {
                _ = try LiveSessionSave(screenID: ids[index], expect: nil, since: nil).perform(sessionID: "s1", channel: channel, foundAppearance: .light, into: into)
            } catch {
                failures.withLock { $0.append("\(ids[index]): \(error)") }
            }
        }

        #expect(failures.withLock(\.self).isEmpty)
        #expect(try Set(WalkbookLoader.load(contentsOf: into).screens.map(\.id)) == Set(ids))
    }

    /// A save waits while another holds the walkbook's lock — writing nothing meanwhile — and then loads what the holder wrote and keeps it.
    ///
    /// The bounded wait only looks for a save that did not wait; a save that waits never finishes inside it, however slow the machine.
    @Test
    func aSaveWaitsForTheWalkbooksLockAndKeepsWhatItsHolderWrote() throws {
        let fixture = try Fixture(state: nil)
        let into = fixture.directory.url.appendingPathComponent("live.walkbook.json")
        let channel = fixture.channel
        let finished = DispatchSemaphore(value: 0)
        let failure = OSAllocatedUnfairLock<String?>(initialState: nil)
        let held = Walkbook(name: "held", appBundleID: "dev.simwalk.route-fixture", screens: [
            Walkbook.Screen(id: "holder", route: [.openURL(url: "simwalk-fixture://detail")], states: [Walkbook.CaptureState(theme: .light)], expect: nil),
        ])

        let waited = try ExclusiveFileLock(file: LiveSessionSave.lockFile(for: into)).withLock {
            DispatchQueue.global().async {
                do {
                    _ = try LiveSessionSave(screenID: "waiter", expect: nil, since: nil).perform(sessionID: "s1", channel: channel, foundAppearance: .light, into: into)
                } catch {
                    failure.withLock { $0 = "\(error)" }
                }
                finished.signal()
            }
            let early = finished.wait(timeout: .now() + 0.5)
            let wroteEarly = FileManager.default.fileExists(atPath: into.path)
            try LiveSessionSave.write(held, to: into)
            return (early, wroteEarly)
        }

        #expect(waited.0 == .timedOut)
        #expect(!waited.1)
        #expect(finished.wait(timeout: .now() + 30) == .success)
        #expect(failure.withLock(\.self) == nil)
        #expect(try WalkbookLoader.load(contentsOf: into).screens.map(\.id) == ["holder", "waiter"])
    }

    /// A save leaves the walkbook and nothing else in its directory: the lock it took is not a file there, which in an app repository would be untracked litter (SimWalk#73).
    @Test
    func aSaveLeavesNothingButTheWalkbookInItsDirectory() throws {
        let fixture = try Fixture(state: nil)
        let book = fixture.directory.url.appendingPathComponent("book", isDirectory: true)
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)

        _ = try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil)
            .perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: book.appendingPathComponent("live.walkbook.json"))

        #expect(try FileManager.default.contentsOfDirectory(atPath: book.path) == ["live.walkbook.json"])
    }

    /// A save through a symlink to a walkbook waits on the lock a save into its target takes, writes the target, and leaves the link a link — nothing new in either directory.
    ///
    /// The bounded wait only looks for a save that did not wait; a save that waits never finishes inside it, however slow the machine.
    @Test
    func aSaveThroughASymlinkedWalkbookLocksAndWritesItsTarget() throws {
        let fixture = try Fixture(state: nil)
        let real = fixture.directory.url.appendingPathComponent("real", isDirectory: true)
        let links = fixture.directory.url.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
        let target = real.appendingPathComponent("live.walkbook.json")
        let link = links.appendingPathComponent("linked.walkbook.json")
        try LiveSessionSave.write(Walkbook(name: "held", appBundleID: "dev.simwalk.route-fixture", screens: [
            Walkbook.Screen(id: "holder", route: [.openURL(url: "simwalk-fixture://detail")], states: [Walkbook.CaptureState(theme: .light)], expect: nil),
        ]), to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let channel = fixture.channel
        let finished = DispatchSemaphore(value: 0)
        let failure = OSAllocatedUnfairLock<String?>(initialState: nil)

        let early = try ExclusiveFileLock(file: LiveSessionSave.lockFile(for: target)).withLock {
            DispatchQueue.global().async {
                do {
                    _ = try LiveSessionSave(screenID: "waiter", expect: nil, since: nil).perform(sessionID: "s1", channel: channel, foundAppearance: .light, into: link)
                } catch {
                    failure.withLock { $0 = "\(error)" }
                }
                finished.signal()
            }
            return finished.wait(timeout: .now() + 0.5)
        }

        #expect(early == .timedOut)
        #expect(finished.wait(timeout: .now() + 30) == .success)
        #expect(failure.withLock(\.self) == nil)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try WalkbookLoader.load(contentsOf: target).screens.map(\.id) == ["holder", "waiter"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: links.path) == ["linked.walkbook.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path) == ["live.walkbook.json"])
    }

    /// A walkbook reached through a symlinked directory locks what its real path does, and a save through it leaves nothing but the walkbook in the real directory.
    @Test
    func aSaveThroughASymlinkedDirectoryLocksTheRealOneAndLeavesNothingInIt() throws {
        let fixture = try Fixture(state: nil)
        let real = fixture.directory.url.appendingPathComponent("real", isDirectory: true)
        let link = fixture.directory.url.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let through = link.appendingPathComponent("live.walkbook.json")

        let lockedBefore = try LiveSessionSave.lockFile(for: through)
        _ = try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil)
            .perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: through)

        #expect(try lockedBefore.path == LiveSessionSave.lockFile(for: real.appendingPathComponent("live.walkbook.json")).path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path) == ["live.walkbook.json"])
        #expect(try WalkbookLoader.load(contentsOf: real.appendingPathComponent("live.walkbook.json")).screens.map(\.id) == ["detail-live"])
    }

    /// SimWalk#76: the walkbook's path is resolved once, so a link retargeted after that look cannot put the lock and the write in different places — the write lands where the one resolution said, and the path is not looked at again.
    @Test
    func aSaveResolvesTheWalkbooksPathOnceAndWritesWhereItSaid() throws {
        let fixture = try Fixture(state: nil)
        let first = fixture.directory.url.appendingPathComponent("first", isDirectory: true)
        let second = fixture.directory.url.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let looks = OSAllocatedUnfairLock(initialState: 0)
        var save = LiveSessionSave(screenID: "detail-live", expect: nil, since: nil)
        save.resolve = { _ in
            let look = looks.withLock { count -> Int in
                count += 1
                return count
            }
            return (look == 1 ? first : second).appendingPathComponent("live.walkbook.json")
        }

        _ = try save.perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: fixture.directory.url.appendingPathComponent("link.walkbook.json"))

        #expect(looks.withLock { $0 } == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.path) == ["live.walkbook.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: second.path).isEmpty)
    }

    /// A save through a relative symlink to a walkbook not yet written waits on the lock a save into the target takes, creates the target, and leaves the link a link.
    ///
    /// `resolvingSymlinksInPath` answers a dangling link with the link itself, which the atomic write would replace with a file while the lock sat on the link's directory.
    @Test
    func aSaveThroughADanglingSymlinkCreatesItsTargetUnderTheTargetsLock() throws {
        let fixture = try Fixture(state: nil)
        let real = fixture.directory.url.appendingPathComponent("real", isDirectory: true)
        let links = fixture.directory.url.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
        let target = real.appendingPathComponent("new.walkbook.json")
        let link = links.appendingPathComponent("dangling.walkbook.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../real/new.walkbook.json")
        let channel = fixture.channel
        let finished = DispatchSemaphore(value: 0)
        let failure = OSAllocatedUnfairLock<String?>(initialState: nil)

        let early = try ExclusiveFileLock(file: LiveSessionSave.lockFile(for: target)).withLock {
            DispatchQueue.global().async {
                do {
                    _ = try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: channel, foundAppearance: .light, into: link)
                } catch {
                    failure.withLock { $0 = "\(error)" }
                }
                finished.signal()
            }
            return finished.wait(timeout: .now() + 0.5)
        }

        #expect(early == .timedOut)
        #expect(finished.wait(timeout: .now() + 30) == .success)
        #expect(failure.withLock(\.self) == nil)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "../real/new.walkbook.json")
        #expect(try WalkbookLoader.load(contentsOf: target).screens.map(\.id) == ["detail-live"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path) == ["new.walkbook.json"])
    }

    /// Symlinks that loop are refused as not writable, naming the walkbook the caller gave, and neither link is replaced by a file.
    @Test
    func aSaveThroughSymlinksThatLoopIsRefusedAndLeavesThemLinks() throws {
        let fixture = try Fixture(state: nil)
        let first = fixture.directory.url.appendingPathComponent("first.walkbook.json")
        let second = fixture.directory.url.appendingPathComponent("second.walkbook.json")
        try FileManager.default.createSymbolicLink(atPath: first.path, withDestinationPath: "second.walkbook.json")
        try FileManager.default.createSymbolicLink(atPath: second.path, withDestinationPath: "first.walkbook.json")

        let error = #expect(throws: LiveSessionSaveError.self) {
            try LiveSessionSave(screenID: "detail-live", expect: nil, since: nil).perform(sessionID: "s1", channel: fixture.channel, foundAppearance: .light, into: first)
        }
        let refused: String? = if case let .notWritable(path, _) = error {
            path
        } else {
            nil
        }

        #expect(refused == first.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: first.path) == "second.walkbook.json")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: second.path) == "first.walkbook.json")
    }
}

extension LiveSessionSaveTests {
    /// A session of four requests: a system tap that landed with its owner, a read, an openURL that landed, and a blocked tap.
    struct Fixture {
        let directory: TemporaryDirectory
        let channel: LiveSessionChannel

        init(state: Walkbook.CaptureState?) throws {
            directory = try TemporaryDirectory()
            channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
            try channel.prepare()
            try channel.writeLaunch(LiveSessionLaunch(appBundleID: "dev.simwalk.route-fixture", state: state))
            _ = try channel.send(.step, step: .systemTap(label: "Allow"))
            _ = try channel.send(.read)
            _ = try channel.send(.step, step: .openURL(url: "simwalk-fixture://detail"))
            _ = try channel.send(.step, step: .tap(label: "Nowhere"))
            let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "RouteFixture")
            let delta = ScreenDelta(from: tree, to: tree)
            try channel.respond(LiveSessionResponse(n: 1, action: .step, step: .landed(.systemTap(label: "Allow", owner: .springboard), delta: delta)))
            try channel.respond(LiveSessionResponse(n: 2, action: .read))
            try channel.respond(LiveSessionResponse(n: 3, action: .step, step: .landed(.openURL(url: "simwalk-fixture://detail"), delta: delta)))
            try channel.respond(LiveSessionResponse(n: 4, action: .step, step: .blocked(reason: nil, delta: delta)))
        }
    }
}
