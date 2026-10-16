//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The store's names, its bound of a hundred, and the promise to delete only what it named.
struct MirrorCaptureStoreTests {
    private func store(_ directory: TemporaryDirectory, pruning: Bool = true) -> MirrorCaptureStore {
        MirrorCaptureStore(directory: directory.url, pruning: pruning)
    }

    private func file(in directory: TemporaryDirectory, _ name: String) throws -> URL {
        let url = directory.url.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    /// A kept capture is `<yyyyMMddTHHmmss-SSSZ> in UTC-<slug>.png` and the scratch file is moved, not copied.
    @Test
    func aKeptCaptureIsNamedByTimeAndLabel() throws {
        let directory = try TemporaryDirectory()
        let store = store(directory)
        let scratch = try store.scratchFile()
        try Data("x".utf8).write(to: scratch)

        let kept = try store.keep(scratch, label: "tap .50,.62", at: Date(timeIntervalSince1970: 1_760_000_000.123))

        #expect(kept.lastPathComponent == "20251009T085320-123Z-tap-50-62.png")
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
        #expect(scratch.deletingLastPathComponent().lastPathComponent == ".scratch")
    }

    /// Two captures in one millisecond do not overwrite each other.
    @Test
    func aNameTakenGetsASuffix() throws {
        let directory = try TemporaryDirectory()
        let store = store(directory)
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let first = try store.scratchFile()
        let second = try store.scratchFile()
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)

        let one = try store.keep(first, label: "read", at: date)
        let two = try store.keep(second, label: "read", at: date)

        #expect(one != two)
        #expect(two.lastPathComponent == "20251009T085320-000Z-read-2.png")
    }

    /// A burst's directory takes the same name without the extension.
    @Test
    func aBurstDirectoryIsNamedLikeACapture() throws {
        let directory = try TemporaryDirectory()
        let burst = try store(directory).burstDirectory(label: "tap .50,.62", at: Date(timeIntervalSince1970: 1_760_000_000))

        #expect(burst.lastPathComponent == "20251009T085320-000Z-tap-50-62")
        #expect(FileManager.default.fileExists(atPath: burst.path))
    }

    /// 105 kept entries (some of them burst directories) prune to the newest 100 by name, and a file the store never named stays.
    @Test
    func pruningKeepsTheNewestHundredAndOnlyWhatItNamed() throws {
        let directory = try TemporaryDirectory()
        let store = store(directory)
        let stranger = try file(in: directory, "notes.txt")
        let lookalike = try file(in: directory, "20200101T000000-000Z.png")
        for second in 0 ..< 104 {
            _ = try file(in: directory, String(format: "20250101T000000-%03dZ-read.png", second))
        }
        let old = try file(in: directory, "20240101T000000-000Z-read.png")
        let scratch = try store.scratchFile()
        try Data("x".utf8).write(to: scratch)

        let kept = try store.keep(scratch, label: "read", at: Date(timeIntervalSince1970: 1_760_000_000))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)

        #expect(names.filter(MirrorCaptureStore.isKeptName).count == 100)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(FileManager.default.fileExists(atPath: stranger.path))
        #expect(FileManager.default.fileExists(atPath: lookalike.path))
    }

    /// An `--out` store writes where it is told and never deletes, however many are there.
    @Test
    func anOutDirectoryNeverPrunes() throws {
        let directory = try TemporaryDirectory()
        let store = store(directory, pruning: false)
        for index in 0 ..< 110 {
            _ = try file(in: directory, String(format: "20250101T000000-%03dZ-read.png", index))
        }
        let scratch = try store.scratchFile()
        try Data("x".utf8).write(to: scratch)

        _ = try store.keep(scratch, label: "read", at: Date(timeIntervalSince1970: 1_760_000_000))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)

        #expect(names.filter(MirrorCaptureStore.isKeptName).count == 111)
    }

    /// Names are UTC, so a clock that goes back (DST, a time-zone move) never orders a newer capture before an older one; a local-time name from the earlier scheme is not the store's to delete.
    @Test
    func namesAreUTCAndOnlyThatPatternIsKept() {
        #expect(MirrorCaptureStore.isKeptName("20251009T085320-123Z-read.png"))
        #expect(MirrorCaptureStore.isKeptName("20251009T085320-123Z-read"))
        #expect(!MirrorCaptureStore.isKeptName("20251009-085320-123-read.png"))
    }

    /// A label with nothing a file name can carry is still named, and a long one is cut.
    @Test
    func aSlugIsAlwaysUsable() {
        #expect(MirrorCaptureStore.slug("...") == "capture")
        #expect(MirrorCaptureStore.slug("menu Home Screen") == "menu-home-screen")
        #expect(MirrorCaptureStore.slug(String(repeating: "a", count: 90)).count == 40)
    }

    /// An `--out` store keeps its scratch in the standard store's, never in the directory a person named.
    @Test
    func anOutStoreScratchesInTheStandardStore() throws {
        let directory = try TemporaryDirectory()

        let out = MirrorCaptureStore.out(directory.url)

        #expect(out.directory == directory.url)
        #expect(out.scratchDirectory == MirrorCaptureStore.standard().scratchDirectory)
        #expect(store(directory).scratchDirectory == directory.url.appendingPathComponent(".scratch", isDirectory: true))
    }

    /// Clearing the scratch removes what a killed call left and nothing the store kept.
    @Test
    func clearingScratchLeavesKeptCaptures() throws {
        let directory = try TemporaryDirectory()
        let store = store(directory)
        let kept = try store.scratchFile()
        try Data("x".utf8).write(to: kept)
        let keptURL = try store.keep(kept, label: "read", at: Date(timeIntervalSince1970: 1_760_000_000))
        let left = try store.scratchFile()
        try Data("x".utf8).write(to: left)

        store.clearScratch()

        #expect(!FileManager.default.fileExists(atPath: left.path))
        #expect(FileManager.default.fileExists(atPath: keptURL.path))
    }
}
