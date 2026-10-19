//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The machine's live sessions: one directory per session under `~/.simwalk/sessions`, laid out by ``LiveSessionLayout``.
///
/// **The only writer of `session.json`.** The runner writes its own records into the same directory; the host's record is written here once the runner's pid is known, and read back by `read`, `end` and `list`.
public struct LiveSessionStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/.simwalk/sessions` — like leases, never moved by `SIMWALK_USAGE_LOG`, since a session another process could not see would not keep a second one off its device. Under the account home (``HomeDirectories/account()``), not `HOME`, for the same reason.
    public static func standard() -> LiveSessionStore {
        LiveSessionStore(directory: HomeDirectories.account()
            .appendingPathComponent("sessions", isDirectory: true))
    }

    public func layout(id: String) -> LiveSessionLayout {
        LiveSessionLayout(directory: directory.appendingPathComponent(id, isDirectory: true))
    }

    /// Creates session `id`'s directory and its channel; refuses an id already present rather than sharing a directory.
    public func create(id: String) throws -> LiveSessionLayout {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let layout = layout(id: id)
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: false)
        try LiveSessionChannel(layout: layout).prepare()
        return layout
    }

    /// Where a `session start` claims `udid` while it builds, settles and spawns (``LiveSessionClaim``) — under `.claims`, which `all()` passes over as it does every dot-named entry.
    public func claim(udid: String) -> URL {
        claimsDirectory.appendingPathComponent(udid)
    }

    /// The directory every ``claim(udid:)`` is in.
    public var claimsDirectory: URL {
        directory.appendingPathComponent(".claims", isDirectory: true)
    }

    public func write(_ record: LiveSessionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: layout(id: record.id).record, options: .atomic)
    }

    /// Session `id`'s record; `nil` when there is no such session, or it has no readable record.
    public func record(id: String) -> LiveSessionRecord? {
        guard let data = try? Data(contentsOf: layout(id: id).record) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LiveSessionRecord.self, from: data)
    }

    /// Every session directory, by id; a directory with no readable record is listed with none.
    public func all() -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { Entry(id: $0, record: record(id: $0)) }
    }

    public func remove(id: String) throws {
        try FileManager.default.removeItem(at: layout(id: id).directory)
    }
}

public extension LiveSessionStore {
    struct Entry: Equatable, Sendable {
        public let id: String
        public let record: LiveSessionRecord?
    }
}
