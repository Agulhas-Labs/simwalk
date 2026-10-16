//
// Copyright © Agulhas Labs
//

import Foundation

/// The `UIContentSizeCategory` names accepted by `Walkbook.CaptureState.dynamicTypeSize`.
///
/// Spelled out rather than read from `UIContentSizeCategory` because `SimWalkCore` is a macOS library and cannot import UIKit — and because these are wire constants either way: the value is handed to the app's `-UIPreferredContentSizeCategoryName` launch argument verbatim, so what matters is the string the simulator honours, not a symbol the host happens to have.
public struct ContentSizeCategoryName {
    /// Every accepted name, smallest first.
    public static let all: [String] = [
        "UICTContentSizeCategoryXS",
        "UICTContentSizeCategoryS",
        "UICTContentSizeCategoryM",
        "UICTContentSizeCategoryL",
        "UICTContentSizeCategoryXL",
        "UICTContentSizeCategoryXXL",
        "UICTContentSizeCategoryXXXL",
        "UICTContentSizeCategoryAccessibilityM",
        "UICTContentSizeCategoryAccessibilityL",
        "UICTContentSizeCategoryAccessibilityXL",
        "UICTContentSizeCategoryAccessibilityXXL",
        "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    /// SwiftUI's `DynamicTypeSize` case names, mapped to the platform name meaning the same size.
    ///
    /// Not accepted as input — an alias silently doing the right thing is how the two spellings stayed confusable in the first place. They exist so a refusal can name the value the author almost certainly meant, which is the difference between a rejection that teaches and one that only blocks.
    static let swiftUIAliases: [String: String] = [
        "xSmall": "UICTContentSizeCategoryXS",
        "small": "UICTContentSizeCategoryS",
        "medium": "UICTContentSizeCategoryM",
        "large": "UICTContentSizeCategoryL",
        "xLarge": "UICTContentSizeCategoryXL",
        "xxLarge": "UICTContentSizeCategoryXXL",
        "xxxLarge": "UICTContentSizeCategoryXXXL",
        "accessibility1": "UICTContentSizeCategoryAccessibilityM",
        "accessibility2": "UICTContentSizeCategoryAccessibilityL",
        "accessibility3": "UICTContentSizeCategoryAccessibilityXL",
        "accessibility4": "UICTContentSizeCategoryAccessibilityXXL",
        "accessibility5": "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    /// Whether the simulator would honour this name.
    public static func isValid(_ name: String) -> Bool {
        all.contains(name)
    }

    /// The name the author probably meant, when a rejected value is recognisably a near miss.
    ///
    /// Two misses are worth naming: SwiftUI's spelling for the same size, and a correct name in the wrong case. Anything else returns `nil` rather than guessing — a suggestion that is wrong costs more than none, because it is followed.
    public static func suggestion(for name: String) -> String? {
        if let alias = swiftUIAliases[name] {
            return alias
        }
        if let aliasIgnoringCase = swiftUIAliases.first(where: { $0.key.lowercased() == name.lowercased() })?.value {
            return aliasIgnoringCase
        }
        return all.first { $0.lowercased() == name.lowercased() }
    }
}
