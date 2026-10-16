//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// Stable pseudonyms for the failure reasons a shared `simwalk usage` report must not carry.
///
/// A report is built to be pasted — into a session, a ticket, an issue — and a failure reason quotes whatever the call was pointed at: a walkbook path, a bundle directory, a bundle ID, a device name, the runner's own output. Under redaction the counts, kinds and dates stay and each reason becomes a salted-hash token, `reason-3f2a1b`. The salt is per machine and reused, so one reason carries one token from this report to the next — a reason still costing walks next week reads as the same row, not as churn — while nobody off the machine can test a guessed sentence against a token. Redaction is the default; the owner decodes by re-running with `--unredact`, and the two reports line up row for row because both are ordered by the real text.
///
/// The same design as sift's own usage report, copied rather than depended on: one tool must not need the other installed to be honest about itself.
public struct Redactor: Sendable {
    private let salt: Data

    public init(salt: Data) {
        self.salt = salt
    }

    // Host-only for the reason `UsageLog.standard()` is: the salt lives beside the usage log, and that
    // location is a fact about the host.
    #if os(macOS)
    /// The redactor for this machine, backed by a salt beside the usage log, created once and reused.
    ///
    /// An unwritable salt file degrades to a fresh salt per run — tokens still hold within that report, they just stop agreeing with the next one.
    ///
    /// Created with `O_CREAT|O_EXCL`, never overwritten: a plain `write(to:options:.atomic)` is last-writer-wins, so of several processes racing to create the file the ones that lose keep the salt they generated in memory and key their tokens off bytes nobody else's report shares — of six parallel first runs, one trial saw exactly that. `O_EXCL` makes losing the race a fact the loser can act on: it re-reads the winner's bytes instead of quietly using its own.
    public static func standard(saltFile: URL = defaultSaltFile) -> Redactor {
        if let data = try? Data(contentsOf: saltFile), !data.isEmpty {
            return Redactor(salt: data)
        }
        try? FileManager.default.createDirectory(at: saltFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0 ..< saltLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        if Self.createExclusively(saltFile, contents: salt) {
            return Redactor(salt: salt)
        }
        // Lost the race (EEXIST), or could not create it for some other reason: read back whatever is
        // there now rather than key this run's tokens off a salt nobody else's report shares.
        if let data = try? Data(contentsOf: saltFile), !data.isEmpty {
            return Redactor(salt: data)
        }
        return Redactor(salt: salt)
    }

    /// Creates `url` at mode 0600 with `O_CREAT|O_EXCL` and writes `contents` in one call — `false` when another process already holds the name (`EEXIST`) or the write could not be completed, either of which leaves the caller to re-read rather than trust bytes that were never durably written.
    private static func createExclusively(_ url: URL, contents: Data) -> Bool {
        let descriptor = url.path.withCString { path in
            open(path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        }
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return contents.withUnsafeBytes { buffer -> Bool in
            guard var pointer = buffer.baseAddress else { return true }
            var remaining = buffer.count
            while remaining > 0 {
                let written = write(descriptor, pointer, remaining)
                guard written > 0 else {
                    if written < 0, errno == EINTR {
                        continue
                    }
                    return false
                }
                pointer += written
                remaining -= written
            }
            return true
        }
    }

    /// Beside the usage log — so a log moved by `SIMWALK_USAGE_LOG` takes its salt with it, and a scratch run never writes into the real `~/.simwalk`.
    public static var defaultSaltFile: URL {
        UsageLog.standard().directory.appendingPathComponent("redaction-salt")
    }

    /// 32 bytes — a salt as long as the digest it keys, so it is never the weaker half.
    private static var saltLength: Int {
        32
    }
    #endif

    /// A failure reason's pseudonym — identical reasons share a token, so grouping survives redaction.
    public func reason(_ text: String) -> String {
        token("reason", text)
    }

    /// Domain-separated so a token for one kind of name could never be matched against a token for another, and six hex characters because a report holds tens of reasons, not millions.
    private func token(_ prefix: String, _ value: String) -> String {
        var data = salt
        data.append(Data("\(prefix):\(value)".utf8))
        let hex = SHA256.hash(data: data).prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(hex)"
    }
}
