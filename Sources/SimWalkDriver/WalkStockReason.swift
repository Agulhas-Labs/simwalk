//
// Copyright © Agulhas Labs
//

/// Why a walk's devices boot with every service rather than slim.
public enum WalkStockReason: Sendable, Equatable {
    /// The caller asked for the stock boot.
    case requested
    /// No measured profile covers the runtime.
    case noProfile(osVersion: String)
    /// The app's declarations could not be read; the reason names the file.
    case unreadable(String)
    /// The app declares keys no rule maps to a capability, so what it needs is unknown.
    case unmapped([String])

    public var text: String {
        switch self {
        case .requested: "--stock"
        case let .noProfile(osVersion): "no service profile for iOS \(osVersion)"
        case let .unreadable(reason): "the app's declarations could not be read (\(reason))"
        case let .unmapped(keys): "the app declares what no rule maps (\(keys.joined(separator: ", ")))"
        }
    }
}
