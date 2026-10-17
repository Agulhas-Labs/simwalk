//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The simulator's own light or dark appearance: read on the host before a walk, handed to the runner, and put back after.
///
/// **A walk used to leave the device in whatever appearance its last state set.** The runner sets the appearance per state and never reset it, so a walk ending on a dark state left the simulator dark for everything after it — including the next walk, whose `StateApplicationCheck` then had a dark device underneath a failed light/dark comparison and no way to know it. Reading it first is also what makes it *known*: the check decides which side of that comparison can be kept from the device's appearance rather than from how bright a picture is.
///
/// Read through `simctl ui`, on the host, rather than from inside the runner — the host is where a walk begins and ends, so it is the one place that can say what the device was before any state touched it.
public struct DeviceAppearance {
    /// The device's appearance as `simctl` reports it, or `nil` when it could not be read, named something this tool has no theme for, or was cut short.
    ///
    /// Throws only what ``reading(udid:run:)`` throws: a read stalled behind `xcodebuild -runFirstLaunch`.
    public static func read(udid: String, run: (String, [String]) throws -> Shell.Result) throws -> Walkbook.Theme? {
        guard case let .reported(theme) = try reading(udid: udid, run: run) else { return nil }
        return theme
    }

    /// What asking `simctl` for the device's appearance came to — with an answer cut short at a bounded call's drain limit, and a call that did not run to a reported answer at all (a non-zero exit or a thrown error, a timeout included), each told apart from an answer the device gave (SimWalk#30, SimWalk#32).
    ///
    /// **A judgement that compares the appearance with an expected one reads this, not `read`.** Neither a cut-short nor a failed answer parses as anything the device said — "the device read nothing" beside an expected `light` is not a mismatch to hold the device to; only `.reported` carries one.
    ///
    /// **A read stalled behind `xcodebuild -runFirstLaunch` is thrown, not `.failed`** (SimWalk#136): every `simctl` call after it would stall the same way, so it is a cause to name, where a plain timeout is one device's read gone missing.
    public static func reading(udid: String, run: (String, [String]) throws -> Shell.Result) throws -> Reading {
        let result: Shell.Result
        do {
            result = try run(xcrun, readArguments(udid: udid))
        } catch let ShellError.stalledOnFirstLaunch(command, seconds) {
            throw ShellError.stalledOnFirstLaunch(command: command, seconds: seconds)
        } catch {
            return .failed
        }
        guard result.succeeded else { return .failed }
        guard !result.truncated else { return .cutShort }
        return .reported(Walkbook.Theme(rawValue: result.standardOutput.trimmed))
    }

    /// Puts the device back in `theme` and reads it back, answering what happened.
    public static func restore(_ theme: Walkbook.Theme, udid: String, run: (String, [String]) throws -> Shell.Result) -> Handback {
        guard let written = try? run(xcrun, setArguments(theme, udid: udid)), written.succeeded else {
            return .failed(found: theme, reason: "setting it did not succeed")
        }
        let readBack: Reading
        do {
            readBack = try reading(udid: udid, run: run)
        } catch {
            return .unconfirmed(found: theme, reason: "it was set, but reading it back stalled (\(error))")
        }
        return switch readBack {
        case .reported(theme):
            .restored(theme)
        case .cutShort:
            .unconfirmed(found: theme, reason: "it was set, but reading it back was cut short, so nothing confirms it")
        case .failed:
            .unconfirmed(found: theme, reason: "it was set, but reading it back failed, so nothing confirms it")
        case .reported:
            .failed(found: theme, reason: "it did not read back as \(theme.rawValue)")
        }
    }

    /// `simctl ui <udid> appearance`, which prints `light` or `dark`.
    public static func readArguments(udid: String) -> [String] {
        ["simctl", "ui", udid, "appearance"]
    }

    /// `simctl ui <udid> appearance <theme>`.
    public static func setArguments(_ theme: Walkbook.Theme, udid: String) -> [String] {
        readArguments(udid: udid) + [theme.rawValue]
    }

    /// The command a person runs to do what a restore does.
    public static func command(_ theme: Walkbook.Theme, udid: String) -> String {
        "xcrun \(setArguments(theme, udid: udid).joined(separator: " "))"
    }

    private static var xcrun: String {
        "/usr/bin/xcrun"
    }
}

public extension DeviceAppearance {
    /// What `simctl` said when asked for the device's appearance.
    enum Reading: Equatable, Sendable {
        /// The command ran to a reported answer; the payload is the appearance it named, or `nil` when it named something this tool has no theme for.
        case reported(Walkbook.Theme?)
        /// The command did not run to a reported answer at all — a non-zero exit, or a thrown error such as a timeout — so what the device's appearance is stays unknown; no answer, never a mismatch (SimWalk#32).
        case failed
        /// The command exited, but its output was still held open when the call's drain limit ran out (`Shell.Result.truncated`), so what it said is not known — no answer, rather than a wrong one.
        case cutShort
    }

    /// What a walk did with the device's appearance on the way out.
    enum Handback: Equatable, Sendable {
        /// Put back to what the walk found, and read back as that.
        case restored(Walkbook.Theme)
        /// Not read before the walk, so there was nothing known to put back — and nothing the check could attribute an appearance refusal by.
        case unknown
        /// Read before the walk and could not be put back; the payload says what it was and why.
        case failed(found: Walkbook.Theme, reason: String)
        /// Set, but not confirmed back — the write succeeded and only the read-back is missing, not `failed`, since a cut-short read is no answer rather than a wrong one (SimWalk#30); the payload says what was set and why the read did not confirm it.
        case unconfirmed(found: Walkbook.Theme, reason: String)

        /// The line printed under a walk's answer, or `nil` when the device was simply put back.
        public func note(udid: String) -> String? {
            switch self {
            case .restored:
                nil
            case .unknown:
                "appearance: `simctl ui` did not report \(udid)'s appearance before the walk, so the walk could not put it back, and a light state beside a dark one that did not apply was refused rather than kept"
            case let .failed(found, reason):
                "appearance: \(udid) was \(found.rawValue) before the walk and could not be put back (\(reason)) — run: \(DeviceAppearance.command(found, udid: udid))"
            case let .unconfirmed(found, reason):
                "appearance: \(udid) was \(found.rawValue) before the walk and this walk could not confirm it was put back (\(reason)) — if it did not hold, run: \(DeviceAppearance.command(found, udid: udid))"
            }
        }

        /// What this qualifies the walk's answer by, or `nil` when the device was put back as found.
        public var qualification: String? {
            switch self {
            case .restored:
                nil
            case .unknown:
                "a device appearance that could not be read"
            case .failed:
                "a device appearance that could not be put back"
            case .unconfirmed:
                "a device appearance not confirmed put back"
            }
        }
    }
}
