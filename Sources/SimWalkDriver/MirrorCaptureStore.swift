//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a mirror call's captures live: scratch files while it reads, the served capture kept beside the newest hundred (Brief §8 "The observation").
///
/// **Scratch is emptied at the start of every call**, under the call lock (``clearScratch()``): a call's own `defer` removes its scratch files, but a call killed mid-read never runs it. An `--out` store keeps its scratch in the standard store's (``out(_:)``), so a directory a person named holds only what was kept.
///
/// **Kept captures are named, ordered and bounded.** A name is `<yyyyMMddTHHmmss-SSSZ>-<label slug>.png` (a burst's directory the same without the extension), so a UTC time, so name order is time order whatever the local clock does and pruning to the newest `keepLimit` is a sort. The store deletes only entries matching that pattern: a file someone else put in the directory is never its to remove. An `--out` directory is the same store without pruning, because a person who named a directory keeps what is in it.
public struct MirrorCaptureStore: Sendable {
    /// How many kept captures (a burst's directory counts as one) survive a prune.
    public static let keepLimit = 100

    /// Where kept captures go.
    public let directory: URL
    private let pruning: Bool
    private var scratchOverride: URL?

    /// A store over `directory`, pruning to the newest `keepLimit` unless `pruning` is false (an `--out` directory).
    public init(directory: URL, pruning: Bool = true) {
        self.directory = directory
        self.pruning = pruning
    }

    /// The machine's own store, `~/.simwalk/mirror/captures/`, found as `MirrorCallLock.standard()` finds `~`.
    public static func standard() -> MirrorCaptureStore {
        MirrorCaptureStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".simwalk/mirror/captures", isDirectory: true))
    }

    /// An `--out` store over `directory`: unpruned, with its scratch in the standard store's `.scratch`, emptied there by every call, rather than a `.scratch` left in the caller's directory.
    public static func out(_ directory: URL) -> MirrorCaptureStore {
        var store = MirrorCaptureStore(directory: directory, pruning: false)
        store.scratchOverride = standard().scratchDirectory
        return store
    }

    /// Where intermediate captures go: the store's own `.scratch`, beside the kept ones so a move to a kept name stays on one volume, or the standard store's for an `--out` store.
    public var scratchDirectory: URL {
        scratchOverride ?? directory.appendingPathComponent(".scratch", isDirectory: true)
    }

    /// A fresh path for an intermediate capture in ``scratchDirectory``; the caller removes it once compared.
    public func scratchFile() throws -> URL {
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        return scratchDirectory.appendingPathComponent("\(UUID().uuidString).png")
    }

    /// Removes the scratch directory and everything in it: what a killed call left.
    ///
    /// Only under the call lock, where no other call's scratch can be in use; a failure is left for the next call, since nothing reads what is there.
    public func clearScratch() {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    /// Moves the served capture `file` to its kept name for `label` at `date`, prunes, and answers where it went.
    public func keep(_ file: URL, label: String, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = freeName(label: label, at: date, extension: "png")
        try FileManager.default.moveItem(at: file, to: destination)
        try prune()
        return destination
    }

    /// Makes the directory a burst's frames are captured into, named as a kept capture is without the extension.
    ///
    /// The caller prunes (`prune()`) once the burst is done, so the directory being filled is never counted against its own frames.
    public func burstDirectory(label: String, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = freeName(label: label, at: date, extension: nil)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    /// Removes every entry this store named but the newest `keepLimit`, by name; nothing else, and nothing at all for an `--out` store.
    public func prune() throws {
        guard pruning else { return }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter(Self.isKeptName).sorted()
        for name in names.dropLast(Self.keepLimit) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Whether `name` is one this store would have made: a UTC millisecond timestamp, a slug, and `.png` unless it is a burst's directory.
    static func isKeptName(_ name: String) -> Bool {
        name.range(of: "^[0-9]{8}T[0-9]{6}-[0-9]{3}Z-[a-z0-9-]+(\\.png)?$", options: .regularExpression) != nil
    }

    /// `label` as lower-case letters, digits and single hyphens, `capture` when nothing is left.
    static func slug(_ label: String) -> String {
        var slug = ""
        for character in label.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if slug.last != "-" {
                slug.append("-")
            }
        }
        let trimmed = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "capture" : trimmed
    }

    /// The kept name for `label` at `date` in UTC, so names sort in time order across a clock change or a time-zone move (local time repeats an hour at DST and jumps with the zone, and a prune would delete the newer entries first), with `-2`, `-3` … before the extension when two land in the same millisecond.
    private func freeName(label: String, at date: Date, extension fileExtension: String?) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss-SSS'Z'"
        let base = "\(formatter.string(from: date))-\(Self.slug(label))"
        var attempt = 1
        while true {
            let stem = attempt == 1 ? base : "\(base)-\(attempt)"
            let url = directory.appendingPathComponent(fileExtension.map { "\(stem).\($0)" } ?? stem)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            attempt += 1
        }
    }
}
