//
// Copyright © Agulhas Labs
//

import Foundation

/// The single generator of every timestamp SimWalk writes or reads: ISO-8601 in UTC, **with fractional seconds**.
///
/// Fractional seconds are not decoration. A manifest's `startedAt`/`finishedAt` must survive a round trip — a `Date` carries sub-second precision, and a whole-second format silently rounds it, so a bundle read back would not equal the one written. In the usage log the same digits are what order two calls made in the same second, and ordering is most of what that file is for.
///
/// **Written with milliseconds, read with or without them.** A `Date` is finer than three decimal places, so a value is rounded to what the format can carry *before* it is stored (`millisecondRounded`) rather than being quietly truncated at the encoder — otherwise the round trip is off by microseconds and the equality claim is false. Reading accepts a whole-second stamp too, because refusing one would turn every timestamp written before this existed into a "torn manifest", which is the less honest of the two refusals available.
struct Timestamp {
    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    /// The same instant with no fractional seconds — for a report stating a window's edge, which is read by eye rather than round-tripped, and does not need to reveal the moment it ran down to the millisecond.
    static func wholeSecondString(from date: Date) -> String {
        wholeSecondFormatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        fractionalFormatter().date(from: string) ?? wholeSecondFormatter().date(from: string)
    }

    /// The same instant, rounded to the millisecond this format carries.
    static func millisecondRounded(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// Built per call rather than shared: `ISO8601DateFormatter` is a reference type with mutable options, and this is reached from whichever thread is writing.
    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func wholeSecondFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
