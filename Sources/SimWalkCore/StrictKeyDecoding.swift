//
// Copyright © Agulhas Labs
//

import Foundation

/// Refuses a key a walkbook's decoders do not recognise — at the walk, a screen, a route step or a state — rather than the default `Decodable` behaviour of ignoring it (SimWalk#10).
///
/// A misspelled `textSize` beside a correctly spelled `theme` decoded today, captured the device's default size, and filed it under a slug asserting the size — `walk` even reported `0 state-not-applied`, since nothing had been asked of a state axis it never saw. That is the same silent-discard shape `WalkbookLoader` already refuses a *recognised* key's unrecognised *value* for (`unknownDynamicTypeSize`, `unknownLocale`); this is the one step earlier, where the key itself never reached the field it was meant to fill.
struct StrictKeyDecoding {
    /// Throws when `container` holds a key `allowed` does not name, naming every one found and the nearest one each is probably meant as — or, when `decoder` carries a `WalkbookProblemSink`, records each as a `WalkbookProblem` and returns instead of throwing, so `WalkbookLoader` can report it beside every other problem rather than the decode aborting before they can be listed.
    ///
    /// Checked ahead of decoding any field, so an unknown key comes before the missing required key a misspelling (`them` for `theme`) leaves behind. On the loader's path both are recorded, the key written first and the key missing second (``required(_:forKey:in:decoder:placeholder:)``); on a bare decode with no sink this throws first, so the name of the key actually written is what is reported.
    static func checkUnknownKeys(in container: KeyedDecodingContainer<AnyCodingKey>, allowing allowed: [String], decoder: Decoder) throws {
        let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }
        guard !unknown.isEmpty else { return }
        if let sink = sink(of: decoder) {
            let path = renderedPath(container.codingPath)
            for key in unknown {
                if let place = misplaced[key] {
                    sink.record(.misplacedKey(path: path, key: key, belongsOn: place))
                } else {
                    sink.record(.unknownKey(path: path, key: key, suggestion: nearest(to: key, among: allowed)))
                }
            }
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: message(for: unknown, allowed: allowed)
        ))
    }

    /// The value `key` holds — or, when `container` has no such key and `decoder` carries a `WalkbookProblemSink`, `placeholder`, the absence recorded as a `WalkbookProblem.missingKey` (round 4).
    ///
    /// **So a missing key stops nothing after it from being listed.** A misspelled required key (`them` for `theme`, `rout` for `route`) is both an unknown key and a missing one, and throwing on the second stopped the decode there — every misspelling further down the walkbook went unreported until the author had fixed this one and run `validate` again. The placeholder is never seen: `WalkbookLoader.load` refuses whenever the sink holds anything, and skips only the checks it stands in for — one screen's, or the walkbook's own top-level fields, never the whole walkbook for one placeholder anywhere in it. With no sink installed this is a plain `decode`, throwing `keyNotFound` exactly as before. A key that is present with a value of the wrong type still throws either way — there is no key to name as missing.
    static func required<Key: CodingKey, Value: Decodable>(
        _ type: Value.Type,
        forKey key: Key,
        in container: KeyedDecodingContainer<Key>,
        decoder: Decoder,
        placeholder: @autoclosure () -> Value
    ) throws -> Value {
        guard !container.contains(key), let sink = sink(of: decoder) else {
            return try container.decode(type, forKey: key)
        }
        sink.record(.missingKey(path: renderedPath(container.codingPath), key: key.stringValue))
        return placeholder()
    }

    /// The sink `WalkbookLoader.load` installed in `decoder`, or `nil` on every other decode.
    static func sink(of decoder: Decoder) -> WalkbookProblemSink? {
        decoder.userInfo[.walkbookProblemSink] as? WalkbookProblemSink
    }

    /// One sentence naming every unknown key found in a container and what it is probably meant as — never just the first, so a container with two typos is not reported as though it had one.
    static func message(for unknown: [String], allowed: [String]) -> String {
        let clauses = unknown.map { key in
            if let place = misplaced[key] {
                return "'\(key)' (it belongs on \(place))"
            }
            return nearest(to: key, among: allowed).map { "'\(key)' (did you mean '\($0)'?)" } ?? "'\(key)'"
        }
        let takesNone = allowed.isEmpty ? " — this takes no keys" : ""
        return "unknown key\(unknown.count == 1 ? "" : "s") \(clauses.joined(separator: ", "))\(takesNone)"
    }

    /// Keys this format recognises, and the one place each is read — so one written anywhere else (it is only ever a container that does not take it, since a container that does never calls it unknown) is told where it goes rather than offered a near miss from the wrong vocabulary.
    ///
    /// **`expect` is the one entry, and the case it exists for (round 3).** Written beside a route step's case name — the spec's own phrase "`expect` on a walkbook step", read literally — it drew "did you mean 'type'?", which is followed straight into a second error. It is a screen's key because it is checked against every state the screen captures, not against one step.
    private static let misplaced: [String: String] = [
        "expect": "the screen, beside its 'route' and 'states'",
        "expectMenu": "the screen, beside its 'route' and 'states'",
        "figures": "the screen, beside its 'route' and 'states'",
        "oracle": "the walkbook's top level, beside 'screens'",
    ]

    /// `codingPath` rendered as a reader would point at it — `screens[0].route[1].tab` rather than Foundation's own multi-line dump of coding keys, or its `Index 0` spelling of a position.
    static func renderedPath(_ codingPath: [CodingKey]) -> String {
        var rendered = ""
        for key in codingPath where key.intValue != nil || !key.stringValue.isEmpty {
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return rendered
    }

    /// The known key most likely meant by `key` — the one sharing its longest run of characters, ties broken by fewer edits and then by declaration order.
    ///
    /// **A shared token outranks a shorter string, which plain edit distance gets backwards.** `textSize` is 6 edits from `theme` and about 10 from `dynamicTypeSize` — closer to `theme` by count alone, and exactly the wrong answer (SimWalk#10's own example), because `theme` shares nothing with it but single letters where `dynamicTypeSize` shares the whole word `Size`. The longest common substring finds that shared word before either candidate's *other* letters are weighed at all, which is what a reader means by "the key I probably meant" — edit distance only breaks a tie between two candidates that already share as much.
    ///
    /// **Seeded with the words the tool itself uses, checked first (round 2).** `appearance` is `XCUIDevice.shared.appearance`'s own name for the axis `theme` decodes, and `dark`/`light` are a `theme`'s own values — none of the three share a run of characters with `theme` at all, so the generic measure above pointed `appearance` at `dynamicTypeSize` and `dark` at `locale`, both wrong in the specific way SimWalk#10 was about: a suggestion that is followed makes the mistake worse. An alias resolves before the generic measure runs at all, and only when its target is actually one of `known` — so an alias meaningless to this container's vocabulary falls through to the same measure as anything else.
    ///
    /// **No suggestion is better than a far one (round 3).** Every key used to get a suggestion, however little it shared with any — `version` at the top level drew "did you mean 'screens'?" over a single shared letter, and a reader told a key is probably meant as another follows it. A candidate is offered only when the run it shares is at least half the shorter of the two strings and at least two characters, which keeps every typo this format has been seen with (`them`, `labl`, `tabb`, `nam`, `rout`, `setle`, `txt`, `textSize`) and drops what is only a coincidence of letters.
    private static let aliases: [String: String] = [
        "appearance": "theme",
        "dark": "theme",
        "light": "theme",
    ]

    ///
    /// **A transposition is offered too (`ulr` for `url`)**: the same letters in another order share no run with the key they were meant for, and were dropped as a coincidence until `openURL` gave the format a three-letter key.
    static func nearest(to key: String, among known: [String]) -> String? {
        let target = key.lowercased()
        if let alias = aliases[target], known.contains(alias) {
            return alias
        }
        // The same letters in another order (`ulr` for `url`) share no run of two characters with the key
        // they were typed for, so the measure below would drop it as a coincidence; a transposition is the
        // one typo that is never one.
        if let transposed = known.first(where: { $0.lowercased() != target && $0.lowercased().sorted() == target.sorted() }) {
            return transposed
        }
        var best: String?
        var bestShared = -1
        var bestDistance = Int.max
        for candidate in known {
            let shared = longestCommonSubstringLength(candidate.lowercased(), target)
            guard shared >= max(2, (min(candidate.count, key.count) + 1) / 2) else { continue }
            let edits = distance(candidate, key)
            if shared > bestShared || (shared == bestShared && edits < bestDistance) {
                best = candidate
                bestShared = shared
                bestDistance = edits
            }
        }
        return best
    }

    /// The length of the longest run of characters `a` and `b` share, contiguous in both.
    private static func longestCommonSubstringLength(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: b.count + 1)
        var longest = 0
        for i in 1 ... a.count {
            var current = Array(repeating: 0, count: b.count + 1)
            for j in 1 ... b.count where a[i - 1] == b[j - 1] {
                current[j] = previous[j - 1] + 1
                longest = max(longest, current[j])
            }
            previous = current
        }
        return longest
    }

    /// Levenshtein edit distance: the fewest single-character insertions, deletions or substitutions that turn `a` into `b` — the tie-break once the shared substring is equal.
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty {
            return b.count
        }
        if b.isEmpty {
            return a.count
        }
        var previous = Array(0 ... b.count)
        for i in 1 ... a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1 ... b.count {
                current[j] = a[i - 1] == b[j - 1] ? previous[j - 1] : 1 + min(previous[j], current[j - 1], previous[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }
}
