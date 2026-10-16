//
// Copyright © Agulhas Labs
//

import Foundation

/// The services a walkbook's `setup.privacy` may grant or revoke — each one `xcrun simctl privacy` accepts.
///
/// Checked against `simctl help privacy` on Xcode's iOS 27 simulator runtime. `all` is left out on purpose: a walkbook states its plan, and "every service" is a plan the manifest could not name back. HealthKit is not a `simctl privacy` service at all, so a Health sheet stays a route's `systemTap`.
public enum PrivacyServiceName: String, CaseIterable, Sendable {
    case calendar
    case contactsLimited = "contacts-limited"
    case contacts
    case location
    case locationAlways = "location-always"
    case photosAdd = "photos-add"
    case photos
    case mediaLibrary = "media-library"
    case microphone
    case motion
    case reminders
    case siri

    /// The `resetPermissions` resource whose authorization this service grants, or `nil` where it has none (`motion`, `siri`).
    ///
    /// One explicit table, because the two name sets are spelled differently (`media-library` / `mediaLibrary`) and one service can stand for the same resource at two levels (`photos-add` and `photos` are both `photos`).
    public var protectedResource: ProtectedResourceName? {
        switch self {
        case .calendar: .calendar
        case .contactsLimited, .contacts: .contacts
        case .location, .locationAlways: .location
        case .photosAdd, .photos: .photos
        case .mediaLibrary: .mediaLibrary
        case .microphone: .microphone
        case .reminders: .reminders
        case .motion, .siri: nil
        }
    }
}
