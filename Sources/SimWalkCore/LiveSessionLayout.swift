//
// Copyright © Agulhas Labs
//

import Foundation

/// Every path inside one live session's directory, named once for both sides of the channel.
///
/// **The host and the runner never spell a path their own way.** The host creates the directory under `~/.simwalk/sessions/<id>/` and hands the runner its path; the runner, inside the simulator, reads and writes the same host paths directly (Brief §7.4's spike: a runner can see and write the exact directories a driver names). One generator for both sides is `CaptureBundleLayout`'s rule applied to the channel: a request written under one name and polled for under another would be a session that never answers.
public struct LiveSessionLayout: Equatable, Sendable {
    /// The session's own directory.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The host's record of the session: its id, the `xcodebuild` pid, the device and the app (`session.json`).
    public var record: URL {
        directory.appendingPathComponent("session.json")
    }

    /// What the runner launches: the app and the state it is launched under, written by the host before the runner starts.
    public var launch: URL {
        directory.appendingPathComponent("launch.json")
    }

    /// Written by the runner once the app is launched and it is polling for requests.
    public var ready: URL {
        directory.appendingPathComponent("ready.json")
    }

    /// Written by the runner as it stops serving, saying why — an `end`, the idle timeout, or a failure.
    public var exit: URL {
        directory.appendingPathComponent("exit.json")
    }

    /// Rewritten by the runner every few seconds from before the launch until `exit.json`, so a runner that died without one has a stop bounded from above (``LiveSessionHeartbeat``).
    public var heartbeat: URL {
        directory.appendingPathComponent("heartbeat.json")
    }

    /// Written by the host when `session list` has switched the device's accessibility back on for a session whose runner stopped without `end`, saying how that went — so the next `list` reports it rather than touching the device again.
    public var accessibilityHandback: URL {
        directory.appendingPathComponent("accessibility.json")
    }

    /// Where a device's runner learns the address, port and token it listens with (``DeviceSessionBind``), copied by the host into the runner's container, whose directory this layout then names.
    public var bind: URL {
        directory.appendingPathComponent("bind.json")
    }

    /// A device session's token (``DeviceSessionToken``), mode 0600, alone in its file: every frame to the runner carries it, so it is kept out of `session.json`, which a listing reads.
    public var token: URL {
        directory.appendingPathComponent("token")
    }

    /// Where the host sends `xcodebuild`'s own output.
    public var runnerLog: URL {
        directory.appendingPathComponent("runner.log")
    }

    /// The runner's result bundle, read for a diagnosis when it never becomes ready.
    public var resultBundle: URL {
        directory.appendingPathComponent("runner.xcresult", isDirectory: true)
    }

    /// Requests, one file each, numbered from 1.
    public var requests: URL {
        directory.appendingPathComponent("requests", isDirectory: true)
    }

    /// Responses, one file each, numbered as the request they answer.
    public var responses: URL {
        directory.appendingPathComponent("responses", isDirectory: true)
    }

    /// Request `number`'s file.
    public func request(_ number: Int) -> URL {
        requests.appendingPathComponent(Self.fileName(number))
    }

    /// The response to request `number`.
    public func response(_ number: Int) -> URL {
        responses.appendingPathComponent(Self.fileName(number))
    }

    /// The request numbers present in `requests`, ascending — only files named as a request, so a write still in its temporary file is never counted.
    public func requestNumbers() -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: requests.path)) ?? []
        return names.compactMap(Self.number(fromFileName:)).sorted()
    }

    /// `<n>.json`.
    static func fileName(_ number: Int) -> String {
        "\(number).\(fileExtension)"
    }

    /// The number a `<n>.json` name carries; `nil` for anything else, a temporary file included.
    static func number(fromFileName name: String) -> Int? {
        let suffix = ".\(fileExtension)"
        guard name.hasSuffix(suffix), let number = Int(name.dropLast(suffix.count)), number > 0 else { return nil }
        return number
    }

    private static var fileExtension: String {
        "json"
    }
}
