//
// Copyright © Agulhas Labs
//

import Foundation

/// A size read by a human, so a 7 MB bundle does not arrive as eight digits.
///
/// SI units (1000, not 1024) and the same ladder Sift prints, deliberately: the two tools' answers are read in the same session by the same reader, and `43 kB` meaning one thing here and another there is a divergence nobody would think to check for.
public struct ByteSize {
    /// `count` as bytes, kilobytes to one decimal below ten, whole kilobytes, or megabytes to one decimal.
    public static func short(_ count: Int) -> String {
        if count < 1000 {
            return "\(count) B"
        }
        if count < 10000 {
            return String(format: "%.1f kB", Double(count) / 1000)
        }
        if count < 1_000_000 {
            return "\(count / 1000) kB"
        }
        return String(format: "%.1f MB", Double(count) / 1_000_000)
    }
}
