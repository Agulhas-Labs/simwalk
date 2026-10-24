//
// Copyright © Agulhas Labs
//

import Foundation

/// One shard's marks on the walk's clock; a mark is `nil` when the shard never got that far — a shard that failed or was stopped.
public struct ShardTiming: Codable, Equatable, Sendable {
    public var index: Int
    /// The device's UDID.
    public var device: String
    public var origin: Origin
    /// The device was booted, held the app and passed the build check.
    public var readyMs: Int?
    /// The runner's walk began.
    public var runnerStartMs: Int?
    /// The runner's walk ended, however it ended.
    public var runnerEndMs: Int?
    /// The appearance retry's second runner pass began; absent when no retry ran (SimWalk#189).
    public var retryStartMs: Int?
    /// The appearance retry's second runner pass ended, however it ended; absent when no retry ran.
    public var retryEndMs: Int?

    public init(index: Int, device: String, origin: Origin, readyMs: Int? = nil, runnerStartMs: Int? = nil, runnerEndMs: Int? = nil, retryStartMs: Int? = nil, retryEndMs: Int? = nil) {
        self.index = index
        self.device = device
        self.origin = origin
        self.readyMs = readyMs
        self.runnerStartMs = runnerStartMs
        self.runnerEndMs = runnerEndMs
        self.retryStartMs = retryStartMs
        self.retryEndMs = retryEndMs
    }
}

public extension ShardTiming {
    /// Where a shard's device came from, and the state it was found in.
    enum Origin: String, Codable, Sendable {
        case existingBooted = "existing-booted"
        case existingShutDown = "existing-shut-down"
        case cloned
        case created
    }
}
