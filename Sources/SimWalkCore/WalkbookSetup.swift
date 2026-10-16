//
// Copyright © Agulhas Labs
//

import Foundation

public extension Walkbook {
    /// Device preparation the host makes with `simctl` before the runner starts, and hands back afterwards.
    ///
    /// Device-wide state, so a walk applies it only to a device it owns (named by UDID, leased, or booted by the walk) and refuses any other before touching it.
    struct Setup: Codable, Equatable, Sendable {
        /// Services granted or revoked for the walkbook's app, by `PrivacyServiceName`.
        public var privacy: Privacy?
        /// A fixed status bar for the walk; `nil` leaves the device's own.
        public var statusBar: StatusBar?
        /// Increase Contrast switched on for the walk; `nil` or `false` leaves it as found.
        public var increaseContrast: Bool?

        public init(privacy: Privacy? = nil, statusBar: StatusBar? = nil, increaseContrast: Bool? = nil) {
            self.privacy = privacy
            self.statusBar = statusBar
            self.increaseContrast = increaseContrast
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["privacy", "statusBar", "increaseContrast"], decoder: decoder)
            privacy = try container.decodeIfPresent(Privacy.self, forKey: AnyCodingKey("privacy"))
            statusBar = try container.decodeIfPresent(StatusBar.self, forKey: AnyCodingKey("statusBar"))
            increaseContrast = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("increaseContrast"))
        }
    }
}

public extension Walkbook.Setup {
    /// The services to grant and revoke, each a `PrivacyServiceName` raw value.
    struct Privacy: Codable, Equatable, Sendable {
        public var grant: [String]?
        public var revoke: [String]?

        public init(grant: [String]? = nil, revoke: [String]? = nil) {
            self.grant = grant
            self.revoke = revoke
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["grant", "revoke"], decoder: decoder)
            grant = try container.decodeIfPresent([String].self, forKey: AnyCodingKey("grant"))
            revoke = try container.decodeIfPresent([String].self, forKey: AnyCodingKey("revoke"))
        }
    }

    /// The status bar a walk fixes; `clean` is the one Apple's own screenshots show.
    enum StatusBar: String, Codable, Equatable, Sendable {
        case clean
    }

    /// Whether this setup changes anything at all.
    var changesDevice: Bool {
        !(privacy?.grant ?? []).isEmpty || !(privacy?.revoke ?? []).isEmpty || statusBar != nil || increaseContrast == true
    }
}
