//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// One walk's mark on a device, for as long as the walk runs: a simulator walk's or dry run's, a physical device walk's, or `inspect`'s live read.
///
/// **A walk under another's lease token is otherwise invisible** (SimWalk#128). `walk --lease T` records nothing but that lease, and `session end` and `session list` exempt the token of the session they are handing back — its caller still holds it. So when a session's runner dies and the same caller walks under that token, a concurrent handback finds only the lease it exempts and puts accessibility and the appearance back mid-walk, and the walk's later captures are wrong. On a phone, `session end` renews that same lease, so without the claim it would hand the appearance back and empty the runner's container mid-walk. The claim is a file the walk writes whatever lease it runs under, which no token exempts.
///
/// **The claim is judged by its holder's pid**, as ``LiveSessionClaim`` and the leases are: a walk killed with `SIGKILL` cannot remove its own, and a file that outlived its walk would otherwise keep a device from being handed back for good. `take` clears the dead holders' files it finds on the way in.
///
/// **It is a presence marker, not a mutex.** A file per walk in `<leases>/.walks/<udid>/`, named for the holder's pid and a token of its own, so several walks on one device each hold theirs and one releasing leaves the others'. Whether two walks may share a device is the lease's question, not this type's.
public struct WalkClaim: Sendable {
    public let file: URL

    /// Takes a claim on `udid` for `holder`, and clears the files of holders no longer alive from that device's directory.
    public static func take(udid: String, in leases: LeaseStore, holder: Int32 = getpid(), isAlive: (Int32) -> Bool = HolderProcess.isAlive) throws -> WalkClaim {
        let directory = directory(of: udid, in: leases)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names(in: directory) where !holderIsAlive(directory.appendingPathComponent(name), isAlive: isAlive) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        let file = directory.appendingPathComponent("\(holder)-\(UUID().uuidString)")
        try Data("\(holder)\n".utf8).write(to: file, options: .atomic)
        return WalkClaim(file: file)
    }

    /// The devices with at least one claim whose holder is alive; reads only.
    public static func walkedDevices(in leases: LeaseStore, isAlive: (Int32) -> Bool) -> Set<String> {
        let root = root(in: leases)
        let udids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return Set(udids.filter { udid in
            let directory = root.appendingPathComponent(udid)
            return names(in: directory).contains { holderIsAlive(directory.appendingPathComponent($0), isAlive: isAlive) }
        })
    }

    /// Removes this claim's own file and nothing else.
    ///
    /// **The device's directory stays**, empty or not: a check that it is empty and its removal are two steps, and another walk's `take` can create its directory and write its claim between them — a removal would then take that claim with it, or fail its write. One empty directory per device ever walked is the cost.
    public func release() {
        try? FileManager.default.removeItem(at: file)
    }

    private static func root(in leases: LeaseStore) -> URL {
        leases.directory.appendingPathComponent(".walks")
    }

    private static func directory(of udid: String, in leases: LeaseStore) -> URL {
        root(in: leases).appendingPathComponent(udid)
    }

    private static func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    /// Whether the pid a claim file names first is alive; a file that names none is not.
    private static func holderIsAlive(_ file: URL, isAlive: (Int32) -> Bool) -> Bool {
        let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return contents.split(whereSeparator: \.isWhitespace).first.flatMap { Int32($0) }.map(isAlive) ?? false
    }
}
