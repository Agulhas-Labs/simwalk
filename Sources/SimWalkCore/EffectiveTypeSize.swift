//
// Copyright © Agulhas Labs
//

import Foundation

/// The Dynamic Type size a capture was taken at: its state's `dynamicTypeSize` when the state sets one, otherwise the size the device was already at (SimWalk#288).
///
/// **One answer for everything keyed on a capture's type size.** A walk run after `simctl ui <udid> content_size accessibility-extra-large` captures every screen at that size whatever its states say, so a rule that read only the state's own size judged none of them. The device's size is the manifest's `Device.contentSize`, in the `UICTContentSizeCategory…` spelling a state uses, so one vocabulary is in the bundle.
///
/// Both forms of a state are accepted because the audit's rows carry only the slug: `dt_<name>` in a slug is the state's `dynamicTypeSize`, lowercased by `CaptureBundleLayout.slugSegment`.
public struct EffectiveTypeSize {
    private static var slugPrefix: String {
        "dt_"
    }

    /// The size, lowercased, or `nil` when neither the state nor the device names one.
    ///
    /// - Parameter dynamicTypeSize: The state's own `dynamicTypeSize`, if it sets one.
    /// - Parameter device: The device's size as the manifest records it, if it does.
    public static func name(dynamicTypeSize: String?, device: String?) -> String? {
        (dynamicTypeSize ?? device)?.lowercased()
    }

    /// The same answer for a state known by its slug.
    public static func name(stateSlug: String, device: String?) -> String? {
        name(dynamicTypeSize: slugSize(stateSlug), device: device)
    }

    /// Whether the capture was taken at an accessibility size, the state's or the device's.
    public static func isAccessibility(stateSlug: String, device: String?) -> Bool {
        name(stateSlug: stateSlug, device: device)?.contains("accessibility") == true
    }

    /// Whether the capture was taken at the default size: no state size, and a device that is at the default or not known.
    public static func isDefault(stateSlug: String, device: String?) -> Bool {
        slugSize(stateSlug) == nil && (device == nil || device == ContentSizeCategoryName.defaultName)
    }

    private static func slugSize(_ stateSlug: String) -> String? {
        stateSlug.split(separator: "-").first { $0.hasPrefix(slugPrefix) }.map { String($0.dropFirst(slugPrefix.count)) }
    }
}
