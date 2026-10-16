//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The exact `simctl` vectors a walkbook's `setup` makes and hands back.
struct DeviceSetupTests {
    @Test
    func eachSetupItemAndItsHandbackRunTheirExactVectors() throws {
        let device = try FakeDevice()
        let setup = Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"], revoke: ["contacts"]), statusBar: .clean, increaseContrast: true)

        let applied = try DeviceSetup.apply(setup, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run).applied
        let applyCalls = device.calls
        device.calls = []
        let handback = DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)

        #expect(applyCalls == [
            ["simctl", "privacy", "U", "grant", "location", "b.id"],
            ["simctl", "privacy", "U", "revoke", "contacts", "b.id"],
            ["simctl", "status_bar", "U", "list"],
            ["simctl", "status_bar", "U", "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"],
            ["simctl", "ui", "U", "increase_contrast"],
            ["simctl", "ui", "U", "increase_contrast", "enabled"],
        ])
        #expect(device.calls == [
            ["simctl", "privacy", "U", "reset", "location", "b.id"],
            ["simctl", "privacy", "U", "reset", "contacts", "b.id"],
            ["simctl", "status_bar", "U", "clear"],
            ["simctl", "status_bar", "U", "list"],
            ["simctl", "ui", "U", "increase_contrast", "disabled"],
            ["simctl", "ui", "U", "increase_contrast"],
        ])
        #expect(handback.failed.isEmpty)
        #expect(handback.restored == ["status bar override cleared, read back clear", "Increase Contrast put back disabled, read back"])
        #expect(handback.unconfirmed.count == 2)
        #expect(handback.unconfirmed[0].hasPrefix("location reset — not confirmed"))
        #expect(handback.unconfirmed[1].hasPrefix("contacts reset — not confirmed"))
    }

    /// SimWalk#63: a `status_bar clear` that exits 0 with an override still listed is not handed back — the read-back decides, not the exit code.
    @Test
    func aStatusBarClearThatReadsBackAnOverrideIsNotHandedBack() throws {
        let device = try FakeDevice()
        device.clearIgnored = true
        let applied = try DeviceSetup.apply(Walkbook.Setup(statusBar: .clean), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run).applied

        let handback = DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)

        #expect(handback.restored.isEmpty)
        #expect(handback.failed == ["xcrun simctl status_bar U clear (it read back an override still set: Time: 09:41)"])
        #expect(DeviceSetup.Report(applied: applied, handback: handback).qualifications == ["a setup change not handed back"])
    }

    /// SimWalk#63: an override the device had before the walk is read first and said, since the handback's clear takes it too — handed back, but not as found.
    @Test
    func anOverrideFoundBeforeTheWalkIsSaidAndItsClearIsNotConfirmedAsFound() throws {
        let device = try FakeDevice()
        device.override = ["Time: 10:00"]
        let applied = try DeviceSetup.apply(Walkbook.Setup(statusBar: .clean), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run).applied

        let handback = DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)

        #expect(applied.statusBarFound == ["Time: 10:00"])
        #expect(applied.line.contains("over an override the device already had (Time: 10:00)"))
        #expect(handback.restored.isEmpty)
        #expect(handback.unconfirmed.first?.contains("the override the device had before the walk (Time: 10:00) is cleared with it, not restored") == true)
        #expect(DeviceSetup.Report(applied: applied, handback: handback).qualifications == ["a setup change handed back but not confirmed as found"])
    }

    /// SimWalk#63: a privacy reset exits 0 but nothing reads a grant back, and it loses one the device had — handed back, not confirmed, and the walk qualified by it.
    @Test
    func aPrivacyResetIsHandedBackUnconfirmedAndQualifiesTheWalk() throws {
        let device = try FakeDevice()
        let applied = try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["photos"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run).applied

        let report = DeviceSetup.Report(applied: applied, handback: DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run))

        #expect(report.handback.restored.isEmpty)
        #expect(report.handback.unconfirmed.count == 1)
        #expect(report.qualifications == ["a setup change handed back but not confirmed as found"])
        #expect(report.record.handedBackUnconfirmed == report.handback.unconfirmed)
        #expect(report.lines.contains { $0.hasPrefix("⚠ setup handed back: photos reset — not confirmed") })
    }

    /// A status bar listing this cannot read says neither whether an override was there nor what a clear would take, so the setup refuses before overriding.
    @Test
    func anUnreadableStatusBarListingRefusesBeforeTheOverride() throws {
        let device = try FakeDevice()
        device.listing = "something else\n"

        #expect {
            try DeviceSetup.apply(Walkbook.Setup(statusBar: .clean), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run).applied
        } throws: { error in
            "\(error)".contains("xcrun simctl status_bar U list")
        }
        #expect(!device.calls.contains(DeviceSetup.statusBarArguments(udid: "U")))
    }

    /// SimWalk#63: each change is on disk before the step that makes it, so a walk killed mid-step leaves it named; the record goes once the handback put everything back.
    @Test
    func eachChangeIsRecordedBeforeItIsMadeAndTheRecordGoesWithTheHandback() throws {
        let scratch = try TemporaryDirectory()
        let written = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let journal = DeviceSetupJournal(directory: scratch.url, pid: 42, token: "walk", now: { written })
        let device = try FakeDevice()
        var seenAtOverride: DeviceSetupJournal.Entry?
        device.onCall = { arguments in
            if arguments == DeviceSetup.statusBarArguments(udid: "U") {
                seenAtOverride = journal.entry(onDevice: "U")
            }
        }
        let setup = Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"]), statusBar: .clean, increaseContrast: true)

        let applied = try DeviceSetup.apply(setup, udid: "U", bundleID: "b.id", journal: journal, run: device.run).applied
        let afterApply = journal.entry(onDevice: "U")
        _ = DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: journal, run: device.run)

        #expect(seenAtOverride?.applied.statusBar == true)
        #expect(seenAtOverride?.applied.privacy == [DeviceSetup.Change(action: "grant", service: "location")])
        #expect(seenAtOverride?.applied.increaseContrastFound == nil)
        #expect(afterApply == DeviceSetupJournal.Entry(udid: "U", bundleID: "b.id", pid: 42, token: "walk", applied: applied, recordedAt: written))
        #expect(journal.entry(onDevice: "U") == nil)
    }

    /// A handback with a command that failed keeps the record, so what it could not put back is still on disk.
    @Test
    func aHandbackThatFailsKeepsTheRecord() throws {
        let scratch = try TemporaryDirectory()
        let journal = DeviceSetupJournal(directory: scratch.url, pid: 42)
        let device = try FakeDevice()
        device.clearIgnored = true
        let applied = try DeviceSetup.apply(Walkbook.Setup(statusBar: .clean), udid: "U", bundleID: "b.id", journal: journal, run: device.run).applied

        _ = DeviceSetup.handBack(applied, udid: "U", bundleID: "b.id", journal: journal, run: device.run)

        #expect(journal.entry(onDevice: "U")?.applied == applied)
    }

    /// SimWalk#63 review: a journal that cannot be written refuses the change it was for, and the change is not made.
    @Test
    func aChangeThatCannotBeRecordedIsNotMade() throws {
        let device = try FakeDevice()
        try Data("not a directory".utf8).write(to: device.journal.directory)

        #expect {
            try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["photos"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)
        } throws: { error in
            if case .notRecorded? = error as? DeviceSetupError {
                true
            } else {
                false
            }
        }
        #expect(!device.calls.contains { $0.starts(with: ["simctl", "privacy", "U", "grant"]) })
    }

    /// SimWalk#73 item 5: a refusal that already carries the leftover's handback lines keeps them when the earlier steps' handback is added.
    @Test
    func aNotRecordedRefusalKeepsItsEarlierHandbackLines() {
        let refused = DeviceSetupError.notRecorded(path: "p", reason: "r", handback: ["leftover handed back"])

        #expect(refused.handingBack(["earlier steps handed back"]) == .notRecorded(path: "p", reason: "r", handback: ["leftover handed back", "earlier steps handed back"]))
    }

    /// SimWalk#72: a record whose walk is gone — a dead pid, or an earlier walk in this process — is handed back before the first change, for its own app, and said and qualified; then this walk's own record takes its place.
    @Test(arguments: [Int32.max, getpid()])
    func aLeftoverWhoseWalkIsGoneIsHandedBackFirstAndQualifiesTheWalk(pid: Int32) throws {
        let device = try FakeDevice()
        let leftover = DeviceSetup.Applied(privacy: [DeviceSetup.Change(action: "grant", service: "photos")], statusBar: true)
        try device.plant(DeviceSetupJournal.Entry(udid: "U", bundleID: "killed.id", pid: pid, token: "killed", applied: leftover))

        let made = try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)
        let written = device.journal.entry(onDevice: "U")
        let report = DeviceSetup.Report(applied: made.applied, leftover: made.leftover, handback: DeviceSetup.handBack(made.applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run))

        #expect(Array(device.calls.prefix(4)) == [
            ["simctl", "privacy", "U", "reset", "photos", "killed.id"],
            ["simctl", "status_bar", "U", "clear"],
            ["simctl", "status_bar", "U", "list"],
            ["simctl", "privacy", "U", "grant", "location", "b.id"],
        ])
        #expect(written?.token != "killed")
        #expect(written?.bundleID == "b.id")
        #expect(report.qualifications.first == "a setup an earlier walk left on the device, handed back before this one's")
        let line = try #require(report.record.leftover?.first)
        #expect(line.contains("pid \(pid) (\(pid == getpid() ? "an earlier walk in this process" : "no longer running")) made privacy grant photos; status bar clean"))
        #expect(line.contains("for killed.id"))
        #expect(line.contains("not confirmed as found: photos reset"))
        #expect(report.record.leftover?.last == "setup leftover handed back: status bar override cleared, read back clear")
        #expect(device.journal.entry(onDevice: "U") == nil)
    }

    /// SimWalk#72: a record whose walk still runs is refused before any change, naming the pid — and the refusal's handback leaves that record where it was.
    @Test
    func aLeftoverWhoseWalkStillRunsRefusesBeforeAnyChangeAndIsLeftIntact() throws {
        let device = try FakeDevice()
        let running = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: 1, token: "running", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(running)

        #expect {
            try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)
        } throws: { error in
            guard case let .leftoverRecord(_, reason, _)? = error as? DeviceSetupError else { return false }
            return reason.contains("pid 1, which is still running")
        }
        #expect(device.calls.isEmpty)
        #expect(device.journal.entry(onDevice: "U") == running)
    }

    /// SimWalk#72: a leftover whose handback fails is kept and refuses this walk, which would otherwise write over it.
    @Test
    func aLeftoverThatCannotBeHandedBackIsKeptAndRefuses() throws {
        let device = try FakeDevice()
        device.override = ["Time: 09:41"]
        device.clearIgnored = true
        let killed = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: Int32.max, token: "killed", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(killed)

        #expect {
            try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)
        } throws: { error in
            guard case let .leftoverRecord(_, _, handback)? = error as? DeviceSetupError else { return false }
            return handback.contains { $0.contains("xcrun simctl status_bar U clear") }
        }
        #expect(!device.calls.contains { $0.starts(with: ["simctl", "privacy", "U", "grant"]) })
        #expect(device.journal.entry(onDevice: "U") == killed)
    }

    /// SimWalk#72: a record that does not read is moved aside and kept, not deleted, and said — a qualification, never a silent skip.
    @Test
    func anUnreadableLeftoverIsKeptAsideAndQualifiesTheWalk() throws {
        let device = try FakeDevice()
        try FileManager.default.createDirectory(at: device.journal.directory, withIntermediateDirectories: true)
        try Data("{ torn".utf8).write(to: device.journal.url(for: "U"))

        let made = try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)

        guard case let .unreadable(path, keptAt, _)? = made.leftover else {
            Issue.record("expected an unreadable leftover, got \(String(describing: made.leftover))")
            return
        }
        #expect(path == device.journal.url(for: "U").path)
        #expect(try String(contentsOfFile: keptAt, encoding: .utf8) == "{ torn")
        #expect(device.journal.entry(onDevice: "U")?.bundleID == "b.id")
        let report = DeviceSetup.Report(applied: made.applied, leftover: made.leftover, handback: DeviceSetup.Handback())
        #expect(report.qualifications == ["a setup record an earlier walk left that does not read, kept"])
        #expect(report.lines.contains { $0.contains("kept at \(keptAt)") })
    }

    /// SimWalk#73: a walk without a setup hands a gone walk's leftover back on a device it owns, and says so; its record reads "none made", not an empty setup.
    @Test
    func aWalkWithoutASetupHandsBackAGoneWalksLeftoverOnADeviceItOwns() throws {
        let device = try FakeDevice()
        try device.plant(DeviceSetupJournal.Entry(udid: "U", bundleID: "killed.id", pid: Int32.max, token: "killed", applied: DeviceSetup.Applied(increaseContrastFound: "disabled")))
        device.contrast = "enabled"

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: true, leaseLapsed: false, journal: device.journal, run: device.run))
        let report = DeviceSetup.Report(applied: made.applied, leftover: made.leftover, handback: DeviceSetup.handBack(made.applied, udid: "U", bundleID: "b.id", journal: device.journal, run: device.run))

        #expect(device.calls == [["simctl", "ui", "U", "increase_contrast", "disabled"], ["simctl", "ui", "U", "increase_contrast"]])
        #expect(device.contrast == "disabled")
        #expect(device.journal.entry(onDevice: "U") == nil)
        #expect(report.qualifications == ["a setup an earlier walk left on the device, handed back before this walk ran"])
        #expect(report.lines.first == "setup: none made by this walk")
        #expect(report.record.leftover?.first?.contains("handed back before this walk ran, read back as found") == true)
    }

    /// SimWalk#73: a walk without a setup leaves a leftover where it is — never refused, never touched — when its walk still runs, or on a device this walk does not own; either way it qualifies the walk.
    @Test(arguments: [(Int32(1), true), (Int32.max, false)])
    func aWalkWithoutASetupLeavesALeftoverItMayNotHandBackAndQualifies(pid: Int32, owned: Bool) throws {
        let device = try FakeDevice()
        let entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: pid, token: "other", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(entry)

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: owned, leaseLapsed: false, journal: device.journal, run: device.run))

        #expect(made.leftover == .leftInPlace(entry, cause: pid == 1 ? .walkRunning : .notOwned, thisProcess: false))
        #expect(device.calls.isEmpty)
        #expect(device.journal.entry(onDevice: "U") == entry)
        #expect(made.leftover?.qualification == (pid == 1 ? "the device carries a setup pid 1 made, a walk still running" : "the device carries a setup a gone walk left, not handed back"))
    }

    /// SimWalk#75: an earlier walk in this process left a record on a device this walk does not own — it is left in place and said as this process's, never as a process no longer running.
    @Test
    func aWalkWithoutASetupSaysALeftoverFromThisProcessIsAnEarlierWalksInIt() throws {
        let device = try FakeDevice()
        let entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: getpid(), token: "earlier", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(entry)

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: false, leaseLapsed: false, journal: device.journal, run: device.run))

        #expect(device.calls.isEmpty)
        #expect(device.journal.entry(onDevice: "U") == entry)
        let line = try #require(made.leftover?.lines.first)
        #expect(line.contains("pid \(getpid()) (an earlier walk in this process)"))
        #expect(!line.contains("no longer running"))
        #expect(made.leftover?.qualification == "the device carries a setup an earlier walk in this process left, not handed back")
    }

    @Test
    func aLeftoverSaysWhyItWasLeftInPlace() throws {
        let entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: 1, token: "other", applied: DeviceSetup.Applied(statusBar: true))

        let running = try #require(DeviceSetupJournal.Leftover.leftInPlace(entry, cause: .walkRunning, thisProcess: false).lines.first)
        let notOwned = try #require(DeviceSetupJournal.Leftover.leftInPlace(entry, cause: .notOwned, thisProcess: false).lines.first)
        let lapsed = try #require(DeviceSetupJournal.Leftover.leftInPlace(entry, cause: .leaseLapsed, thisProcess: false).lines.first)

        #expect(running.hasSuffix("since the device is that walk's until it hands back"))
        #expect(notOwned.hasSuffix("since it does not own the device to hand it back — the next walk that does will"))
        #expect(lapsed.hasSuffix("since its lease on the device could not be renewed to hand it back — the next walk that holds the lease will"))
        #expect(!lapsed.contains("does not own"))
    }

    @Test
    func aWalkWhoseLeaseLapsedSaysSoNotThatItDoesNotOwnTheDevice() throws {
        let device = try FakeDevice()
        let entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: Int32.max, token: "other", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(entry)

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: false, leaseLapsed: true, journal: device.journal, run: device.run))

        #expect(made.leftover == .leftInPlace(entry, cause: .leaseLapsed, thisProcess: false))
    }

    @Test
    func aRunningWalksRecordIsLeftAsItsWalksEvenWhenTheLeaseLapsed() throws {
        let device = try FakeDevice()
        let entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: 1, token: "other", applied: DeviceSetup.Applied(statusBar: true))
        try device.plant(entry)

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: false, leaseLapsed: true, journal: device.journal, run: device.run))

        #expect(made.leftover == .leftInPlace(entry, cause: .walkRunning, thisProcess: false))
    }

    /// SimWalk#75: a record that does not read, found by a walk without a setup on a device it does not own, is left where it is — not moved aside — and qualifies the walk.
    @Test
    func aWalkWithoutASetupLeavesAnUnreadableLeftoverOnADeviceItDoesNotOwn() throws {
        let device = try FakeDevice()
        try FileManager.default.createDirectory(at: device.journal.directory, withIntermediateDirectories: true)
        try Data("{ torn".utf8).write(to: device.journal.url(for: "U"))

        let made = try #require(try DeviceSetup.settleLeftover(udid: "U", owned: false, leaseLapsed: false, journal: device.journal, run: device.run))

        #expect(try String(contentsOf: device.journal.url(for: "U"), encoding: .utf8) == "{ torn")
        #expect(try FileManager.default.contentsOfDirectory(atPath: device.journal.directory.path) == ["U.json"])
        #expect(device.calls.isEmpty)
        #expect(made.leftover?.qualification == "a setup record an earlier walk left that does not read, left in place")
    }

    /// SimWalk#75: a record whose pid is alive but whose start time cannot be read counts as its walk still running — refused, never handed back mid-capture.
    @Test
    func aRecordWhosePidsStartTimeDoesNotReadCountsAsRunning() throws {
        let scratch = try TemporaryDirectory()
        let processes = FakeSessionProcesses()
        processes.alive = [500]
        processes.startTimeUnreadable = [500]
        let journal = DeviceSetupJournal(directory: scratch.url, pid: 42, token: "walk", processes: processes)
        var entry = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: 500, token: "other", applied: DeviceSetup.Applied(statusBar: true))
        entry.recordedAt = Date(timeIntervalSince1970: 0)
        try FileManager.default.createDirectory(at: scratch.url, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: journal.url(for: "U"))
        var calls: [[String]] = []

        #expect {
            try journal.claim(udid: "U", run: { _, arguments in
                calls.append(arguments)
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }, leaseLapsed: false)
        } throws: { error in
            if case let .leftoverRecord(_, reason, _)? = error as? DeviceSetupError {
                reason.contains("pid 500, which is still running")
            } else {
                false
            }
        }
        #expect(calls.isEmpty)
        #expect(journal.entry(onDevice: "U") == entry)
    }

    /// SimWalk#73: a record is its walk's only while that pid started before it was written — pid 1 alive now, with a record written at 1970, is a pid reused since, handed back as a gone walk's rather than refusing.
    @Test
    func aRecordWhosePidStartedAfterItWasWrittenIsHandedBack() throws {
        let device = try FakeDevice()
        var reused = DeviceSetupJournal.Entry(udid: "U", bundleID: "other.id", pid: 1, token: "reused", applied: DeviceSetup.Applied(statusBar: true))
        reused.recordedAt = Date(timeIntervalSince1970: 0)
        try device.plant(reused)

        let made = try DeviceSetup.apply(Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["location"])), udid: "U", bundleID: "b.id", journal: device.journal, run: device.run)

        guard case let .handedBack(entry, _, thisProcess, _)? = made.leftover else {
            Issue.record("expected the leftover handed back, got \(String(describing: made.leftover))")
            return
        }

        #expect(entry == reused)
        #expect(!thisProcess)
        #expect(device.calls.first == ["simctl", "status_bar", "U", "clear"])
    }

    @Test
    func aFailedStepRefusesNamingTheCommandAndHandsBackWhatWentBefore() throws {
        let scratch = try TemporaryDirectory()
        var calls: [[String]] = []
        let run: (String, [String]) throws -> Shell.Result = { _, arguments in
            calls.append(arguments)
            let fails = arguments.starts(with: ["simctl", "status_bar"]) && arguments.contains("override")
            let listing = arguments.last == "list" ? "Current Status Bar Overrides:\n=============================\n" : ""
            return Shell.Result(status: fails ? 1 : 0, standardOutput: listing, standardError: fails ? "boom\n" : "")
        }
        let setup = Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["photos"]), statusBar: .clean)

        #expect {
            try DeviceSetup.apply(setup, udid: "U", bundleID: "b.id", journal: DeviceSetupJournal(directory: scratch.url), run: run)
        } throws: { error in
            let text = "\(error)"
            return text.contains("xcrun simctl status_bar U override") && text.contains("photos reset")
        }
        #expect(calls.last == ["simctl", "privacy", "U", "reset", "photos", "b.id"])
    }

    /// SimWalk#73 item 6: a record another walk on the device writes after this one looked and before it wrote is refused, not written over — this walk's `now` is read between the two, and the other walk records there.
    @Test
    func arecordAnotherWalkWritesAfterThisOneLookedIsNotWrittenOver() throws {
        let scratch = try TemporaryDirectory()
        let theirs = DeviceSetup.Applied(statusBar: true)
        let other = DeviceSetupJournal(directory: scratch.url, pid: 43, token: "other")
        let journal = DeviceSetupJournal(directory: scratch.url, pid: 42, token: "walk") {
            try? other.record(theirs, udid: "U", bundleID: "b.id")
            return Date(timeIntervalSinceReferenceDate: 812_000_000)
        }

        #expect {
            try journal.record(DeviceSetup.Applied(increaseContrastFound: "0"), udid: "U", bundleID: "b.id")
        } throws: { error in
            if case .notRecorded? = error as? DeviceSetupError {
                true
            } else {
                false
            }
        }
        #expect(journal.entry(onDevice: "U")?.token == "other")
        #expect(journal.entry(onDevice: "U")?.applied == theirs)
    }

    /// SimWalk#76: a `.staged` file a crash left is swept once it is older than the threshold, and one young enough to be a walk's in flight is left.
    @Test
    func aStagedFileACrashLeftIsSweptOnceStaleAndNotBefore() throws {
        let scratch = try TemporaryDirectory()
        let clock = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let old = scratch.url.appendingPathComponent(".U.OLD.staged")
        let young = scratch.url.appendingPathComponent(".U.YOUNG.staged")
        for file in [old, young] {
            try Data("{".utf8).write(to: file)
        }
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-DeviceSetupJournal.staleStagedAge - 60)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-60)], ofItemAtPath: young.path)
        let journal = DeviceSetupJournal(directory: scratch.url, pid: 42, token: "walk") { clock }

        _ = try journal.claim(udid: "U", run: { _, _ in Shell.Result(status: 0, standardOutput: "", standardError: "") }, leaseLapsed: false)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: young.path))
        try journal.record(DeviceSetup.Applied(statusBar: true), udid: "U", bundleID: "b.id")
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: scratch.url.path)) == [".U.YOUNG.staged", "U.json"])
    }

    @Test
    func theStatusBarIsReappliedWithTheSameVector() {
        var calls: [[String]] = []
        let run: (String, [String]) throws -> Shell.Result = { _, arguments in
            calls.append(arguments)
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        }
        var applied = DeviceSetup.Applied()
        applied.statusBar = true

        #expect(DeviceSetup.reapplyStatusBar(applied, udid: "U", run: run) == nil)
        #expect(calls == [DeviceSetup.statusBarArguments(udid: "U")])
    }
}

extension DeviceSetupTests {
    /// A device as `simctl` shows it: the status bar listing measured on iOS 27, overrides a clear removes, and Increase Contrast.
    final class FakeDevice {
        /// Where `journal` writes — a walk's own scratch, gone with the device.
        let scratch: TemporaryDirectory
        let journal: DeviceSetupJournal
        var calls: [[String]] = []
        /// The overrides `list` names, a line each.
        var override: [String] = []
        /// What `list` prints instead of the measured listing, when set.
        var listing: String?
        /// A clear that exits 0 and leaves the override.
        var clearIgnored = false
        var contrast = "disabled"
        var onCall: ([String]) -> Void = { _ in }

        init() throws {
            scratch = try TemporaryDirectory()
            journal = DeviceSetupJournal(directory: scratch.url.appendingPathComponent("setup", isDirectory: true))
        }

        /// Writes `entry` as the record another walk left on the device.
        func plant(_ entry: DeviceSetupJournal.Entry) throws {
            try FileManager.default.createDirectory(at: journal.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: journal.url(for: entry.udid))
        }

        func run(_: String, _ arguments: [String]) throws -> Shell.Result {
            calls.append(arguments)
            onCall(arguments)
            var output = ""
            let rest = Array(arguments.dropFirst(3))
            switch rest.first {
            case "list":
                output = listing ?? (["Current Status Bar Overrides:", "============================="] + override).joined(separator: "\n") + "\n"
            case "clear" where !clearIgnored:
                override = []
            case "override":
                override = ["Time: 09:41"]
            case "increase_contrast" where rest.count == 2:
                contrast = rest[1]
            case "increase_contrast":
                output = "\(contrast)\n"
            default:
                break
            }
            return Shell.Result(status: 0, standardOutput: output, standardError: "")
        }
    }
}
