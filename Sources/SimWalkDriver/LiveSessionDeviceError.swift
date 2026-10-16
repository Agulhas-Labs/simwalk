//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// An exchange with a device session's runner that failed, named with where it was aimed: the device, `[address]:port`, and — after a failed connect — what one `devicectl list devices` read of the tunnel (Brief, "Live sessions on a physical device", ruling 7).
///
/// The address is the record's, read once at start; a tunnel that has come back at another address is a new tunnel the runner never bound, which only a new session can reach.
public struct LiveSessionDeviceError: Error, Equatable, CustomStringConvertible {
    public let failure: DeviceSessionClientError
    public let udid: String
    public let address: String
    public let port: UInt16
    /// The tunnel read after a failed connect; `nil` when the connect succeeded and the failure came after it, so nothing was read.
    public let tunnel: PhysicalDeviceTunnel?
    /// The one line a locked phone adds (``LiveSessionDeviceLock``); `nil` when it was not read, was unlocked, or could not be read.
    public var lockNote: String?

    public init(failure: DeviceSessionClientError, udid: String, address: String, port: UInt16, tunnel: PhysicalDeviceTunnel?, lockNote: String? = nil) {
        self.failure = failure
        self.udid = udid
        self.address = address
        self.port = port
        self.tunnel = tunnel
        self.lockNote = lockNote
    }

    /// `failure`, aimed at `endpoint` on `udid`, with the tunnel read once through `shell` when the connect itself failed — refused, unreachable or timed out.
    public static func diagnosing(_ failure: DeviceSessionClientError, udid: String, endpoint: LiveSessionRecord.DeviceEndpoint, shell: Shell) -> LiveSessionDeviceError {
        let connectFailed = switch failure {
        case .refused, .connectFailed, .connectTimedOut:
            true
        case .badAddress, .closedWithoutAnswer, .noAnswer, .malformedReply:
            false
        }
        return LiveSessionDeviceError(
            failure: failure,
            udid: udid,
            address: endpoint.address,
            port: endpoint.port,
            tunnel: connectFailed ? PhysicalDeviceTunnel.read(udid: udid, shell: shell) : nil
        )
    }

    /// `[address]:port` for an IPv6 address, `address:port` for an IPv4 one.
    public var endpoint: String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    /// What the tunnel read said: a changed address names both, an unchanged one its state; `nil` when no read was made.
    public var tunnelFinding: String? {
        guard let tunnel else { return nil }
        let state = tunnel.state.map { " (state: \($0))" } ?? ""
        guard let current = tunnel.address else {
            return "devicectl list devices shows no tunnel to \(udid)\(state)"
        }
        guard current == address else {
            return "the tunnel came back at \(current); the runner listens on \(address): end the session and start again"
        }
        return "the tunnel is still at \(address)\(state)"
    }

    public var description: String {
        "\(failure) — \(endpoint) on \(udid)" + (tunnelFinding.map { "; \($0)" } ?? "") + (lockNote.map { "\n\($0)" } ?? "")
    }
}

extension LiveSessionDeviceError: UsageFailureClassifiable {
    /// The runner, or the tunnel to it — as ``LiveSessionError``'s runner-exited and no-response cases are.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
