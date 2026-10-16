//
// Copyright © Agulhas Labs
//

import Foundation

/// The frames a device session's host and runner exchange over the tunnel: one JSON object on one line, `\n`-terminated, one each way per connection.
///
/// Host to runner, `{"token": "…", "hello": true}` or `{"token": "…", "request": {"action": "step", "step": …, "guard": "…"}}`; runner to host, `{"ready": …}` for a hello and `{"response": …}` for a request. A connection carries one exchange and is closed by the runner once it has answered (Brief, "Live sessions on a physical device", ruling 3).
///
/// **Both sides read under a cap** and close the connection past it, so neither can be made to buffer without bound: a request is a route step and fits in ``requestCap`` many times over, a reply carries a screen's tree and fits in ``replyCap``.
struct DeviceSessionFrame {
    /// The most a host's frame may run to, newline excluded: 1 MiB.
    static var requestCap: Int {
        1 << 20
    }

    /// The most a runner's reply may run to, newline excluded: 16 MiB.
    static var replyCap: Int {
        16 << 20
    }

    /// `value` on one line, `\n`-terminated, in the session files' own encoding less the pretty-printing that would split it over lines.
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = CaptureBundle.encoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// `line`, its newline already stripped, as a `Value`.
    static func decode<Value: Decodable>(_ type: Value.Type, from line: Data) throws -> Value {
        try CaptureBundle.decoder().decode(type, from: line)
    }
}

extension DeviceSessionFrame {
    /// A host's frame as the runner first reads it: the token alone, checked before anything else in the frame is believed.
    ///
    /// A frame that does not get this far — not JSON, or no token — is closed unanswered, exactly as a wrong token is: what the rest of it says is not this runner's business until it has authenticated.
    struct Presented: Decodable {
        let token: String
    }

    /// A host's frame: a `hello`, or one request.
    struct Inbound: Codable {
        let token: String
        let hello: Bool?
        let request: DeviceSessionRequest?

        init(token: DeviceSessionToken, hello: Bool? = nil, request: DeviceSessionRequest? = nil) {
            self.token = token.hex
            self.hello = hello
            self.request = request
        }
    }

    /// A runner's reply: its ready record for a hello, or a request's response.
    struct Outbound: Codable {
        let ready: LiveSessionReady?
        let response: LiveSessionResponse?

        init(ready: LiveSessionReady? = nil, response: LiveSessionResponse? = nil) {
            self.ready = ready
            self.response = response
        }
    }
}
