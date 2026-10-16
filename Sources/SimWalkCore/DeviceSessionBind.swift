//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a device session's runner listens, and the token it answers to (`bind.json`), written by the host into the runner's container.
///
/// **Not the environment**: the tunnel address does not exist until the runner's test does, and an address read before `xcodebuild` holds the tunnel can belong to one about to drop (Brief, "Live sessions on a physical device", ruling 1). So the host writes this once the runner is installed, and again whenever the address it reads changes; the runner takes the one naming its own session, deletes it — the token is on disk no longer than it takes to read — and binds.
public struct DeviceSessionBind: Codable, Equatable, Sendable {
    /// The session this is for: a file left by an earlier session is not this runner's to bind by.
    public let session: String
    /// The tunnel address, the device's own end of it; never the wildcard, which the LAN can reach.
    public let address: String
    /// The port the host drew for this session.
    public let port: UInt16
    public let token: DeviceSessionToken

    public init(session: String, address: String, port: UInt16, token: DeviceSessionToken) {
        self.session = session
        self.address = address
        self.port = port
        self.token = token
    }
}
