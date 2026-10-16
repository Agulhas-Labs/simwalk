//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore

/// A device session's token in its session directory (``LiveSessionLayout/token``): mode 0600, alone in its file, as ``DeviceSessionToken``'s JSON — a bare string of its hex (Brief, "Live sessions on a physical device", ruling 2).
public struct LiveSessionTokenFile {
    public let url: URL

    public init(layout: LiveSessionLayout) {
        url = layout.token
    }

    /// Creates the file at mode 0600 — never over an existing one — and writes `token` into it.
    public func write(_ token: DeviceSessionToken) throws {
        let bytes = try JSONEncoder().encode(token)
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: bytes)
        try handle.close()
    }

    /// The token the file holds; throws when it is missing or is not a token.
    public func read() throws -> DeviceSessionToken {
        try JSONDecoder().decode(DeviceSessionToken.self, from: Data(contentsOf: url))
    }
}
