//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a device session's runner could not listen, or could not read a host's frame — stated as the exit record's detail when it ends the session.
public enum DeviceSessionError: Error, Equatable, CustomStringConvertible {
    /// The system's random source refused, so no token could be drawn.
    case noRandomBytes(status: OSStatus)
    /// `bind.json` names an address that is not an IPv6 literal.
    case badAddress(String)
    /// A socket call other than the bind failed.
    case socketFailed(call: String, errno: Int32)
    /// The listener could not be bound where `bind.json` said; `EADDRNOTAVAIL` (a tunnel that dropped) is waited past rather than thrown.
    case bindFailed(address: String, port: UInt16, errno: Int32)
    /// No `bind.json` naming this session arrived within the wait.
    case noBind(session: String, path: String, waited: TimeInterval, lastProblem: String?)
    /// An authenticated frame that is not a hello or a request this runner can read; answered as a failure under its number.
    case malformedFrame(reason: String)

    public var description: String {
        switch self {
        case let .noRandomBytes(status):
            "cannot draw a session token: the system's random source failed (OSStatus \(status))"
        case let .badAddress(address):
            "bind.json names '\(address)', which is not an IPv6 address"
        case let .socketFailed(call, code):
            "the session's socket failed in \(call): \(Self.describe(code))"
        case let .bindFailed(address, port, code):
            "cannot listen on [\(address)]:\(port): \(Self.describe(code))"
        case let .noBind(session, path, waited, lastProblem):
            "no bind.json for session \(session) arrived at \(path) within \(Int(waited.rounded())) s\(lastProblem.map { " (last: \($0))" } ?? ""): the host writes it once the runner is installed"
        case let .malformedFrame(reason):
            "the request is not one this runner can read: \(reason)"
        }
    }

    /// An errno as its name in words and its number, so a refusal can be looked up either way.
    static func describe(_ code: Int32) -> String {
        "\(String(cString: strerror(code))) (errno \(code))"
    }
}
