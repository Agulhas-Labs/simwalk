//
// Copyright © Agulhas Labs
//

import Foundation

/// The host's side of a device session's socket: one connection per exchange to the runner listening on the tunnel address, every frame carrying the session's token.
///
/// **Each failure is its own case** (``DeviceSessionClientError``), because the host does different things with them: a refused connect before ready is the runner not yet bound and is tried again in half a second (Brief, "Live sessions on a physical device", ruling 5); after ready it is a runner gone, whose exit record the host copies back; a connection closed without a reply is a wrong token or a runner that died answering.
public struct DeviceSessionClient: Sendable {
    public let address: String
    public let port: UInt16
    public let token: DeviceSessionToken
    /// How long a connect may take before it is given up: a non-blocking connect waited on in `poll(2)`.
    public let connectTimeout: TimeInterval

    public init(address: String, port: UInt16, token: DeviceSessionToken, connectTimeout: TimeInterval = 5) {
        self.address = address
        self.port = port
        self.token = token
        self.connectTimeout = connectTimeout
    }

    /// Asks the runner whether it is ready, answering its ready record.
    ///
    /// Until the runner has bound, this throws ``DeviceSessionClientError/refused`` within milliseconds.
    public func hello(timeout: TimeInterval = 5) throws -> LiveSessionReady {
        let reply = try transact(DeviceSessionFrame.Inbound(token: token, hello: true), timeout: timeout)
        guard let ready = reply.ready else {
            throw DeviceSessionClientError.malformedReply(reason: "a hello was answered without a ready record")
        }
        return ready
    }

    /// Sends `request` and waits up to `timeout` for its response, numbered by the runner.
    public func exchange(_ request: DeviceSessionRequest, timeout: TimeInterval) throws -> LiveSessionResponse {
        let reply = try transact(DeviceSessionFrame.Inbound(token: token, request: request), timeout: timeout)
        guard let response = reply.response else {
            throw DeviceSessionClientError.malformedReply(reason: "a request was answered without a response")
        }
        return response
    }

    /// Sends `frame` on a connection of its own and reads the one reply.
    private func transact(_ frame: DeviceSessionFrame.Inbound, timeout: TimeInterval) throws -> DeviceSessionFrame.Outbound {
        let line: Data
        do {
            line = try DeviceSessionFrame.encode(frame)
        } catch {
            throw DeviceSessionClientError.malformedReply(reason: "the frame could not be encoded: \(error)")
        }
        switch try rawExchange(line, timeout: timeout) {
        case let .line(reply):
            do {
                return try DeviceSessionFrame.decode(DeviceSessionFrame.Outbound.self, from: reply)
            } catch {
                throw DeviceSessionClientError.malformedReply(reason: "\(error)")
            }
        case .closed, .failed:
            throw DeviceSessionClientError.closedWithoutAnswer
        case .timedOut:
            throw DeviceSessionClientError.noAnswer(waited: timeout)
        case .overCap:
            throw DeviceSessionClientError.malformedReply(reason: "the reply runs past \(DeviceSessionFrame.replyCap) bytes without ending")
        }
    }

    /// Connects, writes `bytes` as they are, and reads one reply line; what came back however it ended.
    ///
    /// A write the runner cut short by closing — a frame over its cap — is a connection closed without an answer, not a crash: the socket carries `SO_NOSIGPIPE`.
    func rawExchange(_ bytes: Data, timeout: TimeInterval) throws -> DeviceSessionSocket.LineRead {
        let descriptor = try DeviceSessionSocket.connect(address: address, port: port, timeout: connectTimeout)
        defer { Darwin.close(descriptor) }
        return switch DeviceSessionSocket.send(descriptor, bytes, timeout: timeout) {
        case nil:
            DeviceSessionSocket.readLine(descriptor, cap: DeviceSessionFrame.replyCap, timeout: timeout)
        case ETIMEDOUT:
            .timedOut
        case let code?:
            .failed(code)
        }
    }
}
