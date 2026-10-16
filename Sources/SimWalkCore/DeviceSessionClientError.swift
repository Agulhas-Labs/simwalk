//
// Copyright © Agulhas Labs
//

import Foundation

/// Why the host's exchange with a device session's runner came back without an answer, one case per refusal the host gives.
public enum DeviceSessionClientError: Error, Equatable, CustomStringConvertible {
    /// Nothing listens there: before the runner has bound, in milliseconds, or after it has gone.
    ///
    /// `session start` tries again every half second until the runner listens.
    case refused
    /// The address is not a numeric IPv6 or IPv4 address.
    case badAddress(String)
    /// The connect failed other than by refusal: the address unreachable, the tunnel down.
    case connectFailed(errno: Int32)
    /// The connect neither completed nor failed within the wait.
    case connectTimedOut(waited: TimeInterval)
    /// The runner closed the connection without a reply: the token was wrong, the frame was over its cap, or the runner died answering.
    case closedWithoutAnswer
    /// The runner took the frame and did not answer within the wait.
    case noAnswer(waited: TimeInterval)
    /// The runner's reply is not a frame the host can read, or not the one asked for.
    case malformedReply(reason: String)

    public var description: String {
        switch self {
        case .refused:
            "the session's runner refused the connection: nothing is listening on its address"
        case let .badAddress(address):
            "'\(address)' is not a numeric IP address"
        case let .connectFailed(code):
            "cannot connect to the session's runner: \(DeviceSessionError.describe(code))"
        case let .connectTimedOut(waited):
            "the connection to the session's runner did not complete within \(Int(waited.rounded())) s"
        case .closedWithoutAnswer:
            "the session's runner closed the connection without answering"
        case let .noAnswer(waited):
            "the session's runner did not answer within \(Int(waited.rounded())) s"
        case let .malformedReply(reason):
            "the session's runner answered with something that is not a reply: \(reason)"
        }
    }
}
