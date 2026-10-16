//
// Copyright © Agulhas Labs
//

import Foundation

/// The names `Walkbook.CaptureState.resetPermissions` accepts — one for each iOS case of XCTest's `XCUIProtectedResource`.
///
/// Spelled out rather than read from `XCUIProtectedResource` because `SimWalkCore` is a macOS library and cannot import the iOS test framework, and because the macOS-only cases (`userDesktopDirectory`, `appleEvents`, …) name nothing on an iPhone. The list was checked against the iOS 27 simulator SDK's `XCUIProtectedResource.h`: the eight shared cases, `focus`, `localNetwork`, and the five iOS-family ones. The runner maps each to its case; the raw value is the Swift case name, which is what an author reading Apple's documentation will type.
public enum ProtectedResourceName: String, CaseIterable, Sendable {
    case contacts
    case calendar
    case reminders
    case photos
    case microphone
    case camera
    case mediaLibrary
    case homeKit
    case focus
    case localNetwork
    case bluetooth
    case keyboardNetwork
    case location
    case health
    case userTracking
}
