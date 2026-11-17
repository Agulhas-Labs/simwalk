//
// Copyright © Agulhas Labs
//

import Foundation

/// What `xcrun simctl launch` made of the app after a runner timed out launching it twice, so the one line the walk prints says whether the device or the app is at fault (SimWalk#266).
public enum SimctlLaunchCheck: Equatable, Sendable {
    /// `simctl` launched the app, as this process.
    case launched(pid: Int)
    /// `simctl` answered and refused, or its answer was not a launch; `reason` is the cause it gave.
    case refused(reason: String)
    /// `simctl` refused for a reason of the device's own — an error in CoreSimulator's `SimError` domain, such as a device shut down — rather than the app's.
    case deviceRefused(reason: String)
    /// `simctl` did not answer within its bound.
    case unanswered(seconds: TimeInterval)

    /// Launches `bundleID` on `simulator` with `simctl`, then terminates it, best effort, so the app is not left running.
    ///
    /// Every key of `environment` is prefixed `SIMCTL_CHILD_`, which is how `simctl launch` hands variables to the app. The launch gets the bound ``SimctlBound`` gives its verb.
    public static func perform(on simulator: Simulator, bundleID: String, arguments: [String], environment: [String: String], shell: Shell) -> SimctlLaunchCheck {
        let prefixed = Dictionary(uniqueKeysWithValues: environment.map { ("SIMCTL_CHILD_" + $0.key, $0.value) })
        let outcome: SimctlLaunchCheck
        do {
            let result = try shell.run("/usr/bin/xcrun", ["simctl", "launch", simulator.udid, bundleID] + arguments, environment: prefixed)
            if result.succeeded, let pid = pid(in: result.standardOutput) {
                outcome = .launched(pid: pid)
            } else {
                outcome = refusal(status: result.status, standardError: result.standardError, standardOutput: result.standardOutput)
            }
        } catch let ShellError.timedOut(_, seconds), let ShellError.stalledOnFirstLaunch(_, seconds) {
            outcome = .unanswered(seconds: seconds)
        } catch {
            outcome = .refused(reason: "\(error)")
        }
        _ = try? shell.run("/usr/bin/xcrun", ["simctl", "terminate", simulator.udid, bundleID], timeout: DeviceSettle.handbackBound)
        return outcome
    }

    /// The one line saying which side is at fault, with the context that explains a slow device (` (booted 41 s ago; host load average 990)`) when either figure is known.
    ///
    /// - Parameter attempts: How many runners timed out launching: two when the walk tried again, one when it did not because the runner had already written to its output.
    public func line(attempts: Int, bootedAgo: TimeInterval?, loadAverage: Double?) -> String {
        let context = Self.context(bootedAgo: bootedAgo, loadAverage: loadAverage)
        switch self {
        case let .launched(pid):
            let timedOut = attempts >= 2
                ? "XCUITest timed out launching it twice"
                : "XCUITest timed out launching it, and the walk did not try again because the runner had already written to its output"
            return "the app launches with simctl (pid \(pid)), but \(timedOut): the device was slow to answer XCUITest, not the app — walk again once it settles\(context)"
        case let .refused(reason):
            return "the app did not launch with simctl either (\(reason)): the app or its install, not XCUITest"
        case let .deviceRefused(reason):
            return "simctl could not launch the app on the device either (\(reason)): the device, not the app — walk again once it settles, or reboot it\(context)"
        case let .unanswered(seconds):
            let whole = seconds.rounded() == seconds ? String(Int(seconds)) : String(seconds)
            return "simctl did not launch the app within \(whole) s either: the device itself is not answering — walk again once it settles, or reboot it\(context)"
        }
    }

    /// The Mac's one-minute load average, or `nil` where `getloadavg` cannot say.
    public static var hostLoadAverage: Double? {
        var loads = [Double](repeating: 0, count: 1)
        return getloadavg(&loads, 1) < 1 ? nil : loads[0]
    }

    /// How long `simulator` has been booted at `now`, and the host's load average: the two figures ``line(attempts:bootedAgo:loadAverage:)`` lists, each `nil` where it cannot be read.
    public static func context(for simulator: Simulator, now: Date, shell: Shell) -> (bootedAgo: TimeInterval?, loadAverage: Double?) {
        (simulator.bootedAt(now: now, shell: shell).map { now.timeIntervalSince($0) }, hostLoadAverage)
    }

    private static func context(bootedAgo: TimeInterval?, loadAverage: Double?) -> String {
        var parts: [String] = []
        if let bootedAgo {
            parts.append("booted \(age(bootedAgo)) ago")
        }
        if let loadAverage {
            parts.append("host load average \(load(loadAverage))")
        }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: "; ")))"
    }

    private static func age(_ seconds: TimeInterval) -> String {
        if seconds < 120 {
            return "\(Int(seconds)) s"
        }
        if seconds < 7200 {
            return "\(Int(seconds / 60)) min"
        }
        return "\(Int(seconds / 3600)) h"
    }

    private static func load(_ value: Double) -> String {
        value >= 10 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    /// The pid in `simctl launch`'s `<bundle id>: <pid>` output.
    private static func pid(in output: String) -> Int? {
        guard let last = firstLine(of: output)?.split(separator: ":").last else {
            return nil
        }
        return Int(last.trimmingCharacters(in: .whitespaces))
    }

    /// What a `simctl launch` that failed said, as its cause and whose fault it is.
    ///
    /// Its first line is `An error was encountered processing the command (domain=…, code=…):` and each cause below it may open with `Underlying error (…):`, which name nothing, so the reason is the last line that is neither: `Unable to lookup in current state: Shutdown`, or `The request to open "<bundle id>" failed.` (both read from `simctl` on Xcode 27, 2026-10-25). The domain on the first line says whose fault it is: CoreSimulator's `SimError` is the device's.
    static func refusal(status: Int32, standardError: String, standardOutput: String) -> SimctlLaunchCheck {
        let lines = standardError.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let causes = lines.filter { !$0.hasPrefix("An error was encountered") && !$0.hasPrefix("Underlying error") }
        let reason = causes.last ?? lines.first ?? firstLine(of: standardOutput) ?? "simctl exited \(status)"
        return lines.first?.contains("domain=com.apple.CoreSimulator.SimError") == true ? .deviceRefused(reason: reason) : .refused(reason: reason)
    }

    private static func firstLine(of text: String) -> String? {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}
