//
// Copyright © Agulhas Labs
//

import Foundation

/// How long a `simctl` call may run before it is stopped — chosen here, by the verb, for every `simctl` call SimWalk makes (SimWalk#136).
///
/// **No `simctl` call is unbounded.** Every one of them can wedge: a device whose boot hung (SimWalk#26), or an Xcode whose `simctl` first runs `xcodebuild -runFirstLaunch` and waits there on an administrator password nobody is shown. Unbounded, either turns a walk, an inspect or a session start into a call that never answers. ``Shell/run(_:_:environment:timeout:input:workingDirectory:)`` applies the bound to any `xcrun simctl` call made without one, so a call site, or a `run` closure handed down to the device steps, cannot leave it off by omission; a caller's own bound wins.
///
/// The bounds are generous ceilings, not expected durations: a boot and the wait for it on a cold machine, an install of a large app and a clone of a full device take minutes at worst; everything else `simctl` is asked for answers in seconds.
public struct SimctlBound {
    /// The bound for `arguments` run by `executable`: the verb's when that is `xcrun simctl <verb> …`, else `nil` — the caller's own bound, or none, stands.
    static func seconds(for executable: String, _ arguments: [String]) -> TimeInterval? {
        guard URL(fileURLWithPath: executable).lastPathComponent == "xcrun", arguments.first == "simctl" else {
            return nil
        }
        return seconds(forVerb: arguments.dropFirst().first ?? "")
    }

    /// `boot` 120 s; `bootstatus`, `install` and `clone` 300 s; every other verb 60 s.
    static func seconds(forVerb verb: String) -> TimeInterval {
        switch verb {
        case "boot":
            120
        case "bootstatus", "install", "clone":
            300
        default:
            60
        }
    }
}
