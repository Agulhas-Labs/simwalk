//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a walk's `setup` refused before the runner ran.
public enum DeviceSetupError: Error, Equatable, CustomStringConvertible, UsageFailureClassifiable {
    /// The device may be another session's, so nothing was touched.
    case notOwned(udid: String)
    /// A `simctl` step failed; `handback` says what the earlier steps' handback did.
    case stepFailed(command: String, reason: String, handback: [String])
    /// The next change could not be written into the walk's ``DeviceSetupJournal`` first, so it was not made (SimWalk#63); `handback` says what the earlier steps' handback did.
    case notRecorded(path: String, reason: String, handback: [String])
    /// A setup record another walk left on the device could not be settled before this walk's first change — its walk still running, its handback failed, or it would not read and could not be moved aside — so nothing was made (SimWalk#72); `handback` says what handing it back did.
    case leftoverRecord(path: String, reason: String, handback: [String])

    public var description: String {
        switch self {
        case let .notOwned(udid):
            "setup refused: \(DeviceSetup.notOwned(udid: udid))"
        case let .stepFailed(command, reason, handback):
            (["setup refused before the runner ran: `\(command)` failed (\(reason))"] + handback).joined(separator: " — ")
        case let .notRecorded(path, reason, handback):
            (["setup refused before the runner ran: the next change could not be recorded at \(path) first (\(reason)), and made unrecorded, a walk killed before its handback would leave it with nothing on disk saying so"] + handback).joined(separator: " — ")
        case let .leftoverRecord(path, reason, handback):
            (["setup refused before any change: \(path) holds a setup another walk left on the device (\(reason))"] + handback).joined(separator: " — ")
        }
    }

    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .notOwned:
            .inputRefused
        case .stepFailed, .notRecorded, .leftoverRecord:
            .setupFailed
        }
    }

    /// The same refusal, carrying what the handback of the steps before it did.
    func handingBack(_ lines: [String]) -> DeviceSetupError {
        switch self {
        case .notOwned:
            self
        case let .stepFailed(command, reason, _):
            .stepFailed(command: command, reason: reason, handback: lines)
        case let .notRecorded(path, reason, earlier):
            .notRecorded(path: path, reason: reason, handback: earlier + lines)
        case let .leftoverRecord(path, reason, earlier):
            .leftoverRecord(path: path, reason: reason, handback: earlier + lines)
        }
    }
}
