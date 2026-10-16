//
// Copyright © Agulhas Labs
//

import Foundation
import Security

/// The secret that authenticates every exchange with a device session's runner: 32 random bytes, written as 64 lowercase hex digits.
///
/// **Anything on the Mac can reach the tunnel address** (Brief, "Live sessions on a physical device", ruling 2), so the address and port are no secret and this is the only thing standing between another process and the app under test. The host draws one per session and hands it to the runner in `bind.json`; the runner compares each frame's token with ``matches(_:)``, in constant time, so how long a refusal takes says nothing about how much of a guess was right.
public struct DeviceSessionToken: Equatable, Sendable, CustomStringConvertible {
    /// The 64 lowercase hex digits, as they travel.
    public let hex: String

    /// Adopts `hex` when it is a token as ``random()`` writes one, 64 lowercase hex digits; `nil` otherwise.
    public init?(hex: String) {
        guard hex.utf8.count == Self.byteCount * 2, hex.utf8.allSatisfy(Self.isLowercaseHexDigit) else { return nil }
        self.hex = hex
    }

    /// A new token from the system's secure random source.
    public static func random() throws -> DeviceSessionToken {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw DeviceSessionError.noRandomBytes(status: status)
        }
        return DeviceSessionToken(bytes: bytes)
    }

    /// The token these bytes write as.
    init(bytes: [UInt8]) {
        hex = bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `presented` is this token, compared in time that depends on its length alone.
    ///
    /// Every byte is compared whatever the first difference, so a wrong guess is refused no faster for being wrong early; the length is no secret (it is always 64).
    public func matches(_ presented: String) -> Bool {
        let expected = Array(hex.utf8)
        let given = Array(presented.utf8)
        guard expected.count == given.count else { return false }
        var difference: UInt8 = 0
        for index in expected.indices {
            difference |= expected[index] ^ given[index]
        }
        return difference == 0
    }

    /// Never the secret itself: a token printed into a log or an error would undo keeping it out of the environment and the result bundle.
    public var description: String {
        "DeviceSessionToken(redacted)"
    }

    /// The bytes drawn: 256 bits, past guessing in the life of a session.
    static var byteCount: Int {
        32
    }

    private static func isLowercaseHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a") ... UInt8(ascii: "f")).contains(byte)
    }
}

extension DeviceSessionToken: Codable {
    /// A bare string, refused unless it is a token's 64 lowercase hex digits.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let token = DeviceSessionToken(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "a session token is 64 lowercase hex digits")
        }
        self = token
    }

    /// The 64 hex digits, as a bare string.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
