//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// The locale a device is already in, as the state check needs it (SimWalk#18): the one a walkbook locale state would launch the app in, or nothing.
struct DeviceLocaleTests {
    /// `detail-3`, measured: `AppleLocale` reads `en_GB` and `AppleLanguages` reads `( "en-GB" )` — one locale in two spellings.
    @Test
    func adeviceWhoseRegionAndFirstLanguageAgreeIsInThatLocale() {
        #expect(DeviceLocale.read(udid: "UDID-1", run: Self.device(region: "en_GB", languages: "(\n    \"en-GB\"\n)")) == "en_GB")
    }

    /// A walkbook locale sets both keys, so a device whose two disagree is in no state's conditions but its own — and answers nothing, which refuses as before.
    @Test
    func adeviceWhoseRegionAndFirstLanguageDisagreeIsInNoLocale() {
        #expect(DeviceLocale.read(udid: "UDID-1", run: Self.device(region: "en_GB", languages: "(\n    \"en-US\",\n    \"en-GB\"\n)")) == nil)
    }

    /// `@` keywords on the region and an unquoted language are the same locale, not a disagreement.
    @Test
    func keywordsAndQuotingAreNotADifferentLocale() {
        #expect(DeviceLocale.read(udid: "UDID-1", run: Self.device(region: "fr_FR@rg=frzzzz", languages: "(\n    fr_FR\n)")) == "fr_FR")
    }

    /// A keyword that changes what the device draws makes its locale one no walkbook state reproduces (the SimWalk#18 review): `en_US@rg=gbzzzz` formats as the UK, and read as `en_US` it would file an ignored `en_US` state as applied.
    @Test(arguments: ["en_US@rg=gbzzzz", "en_GB@calendar=buddhist", "ar_EG@numbers=latn", "en_GB@rg=gbzzzz;calendar=japanese"])
    func akeywordThatChangesTheFormatsIsNoLocale(region: String) {
        let language = String(region.prefix(5)).replacingOccurrences(of: "_", with: "-")

        #expect(DeviceLocale.read(udid: "UDID-1", run: Self.device(region: region, languages: "(\n    \"\(language)\"\n)")) == nil)
    }

    /// A key that cannot be read is no evidence of a locale.
    @Test
    func anUnreadableKeyIsNoLocale() {
        let run: (String, [String]) throws -> Shell.Result = { _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "does not exist") }

        #expect(DeviceLocale.read(udid: "UDID-1", run: run) == nil)
    }

    /// A key cut short at the drain limit is no evidence of a locale either (SimWalk#30): the text read by then may be a truncated `en_GB`, not `en_GB` itself, so it is judged the same as unreadable rather than trusted by its prefix.
    @Test
    func atruncatedKeyIsNoLocale() {
        let run: (String, [String]) throws -> Shell.Result = { _, _ in Shell.Result(status: 0, standardOutput: "en_GB\n", standardError: "", truncated: true) }

        #expect(DeviceLocale.read(udid: "UDID-1", run: run) == nil)
    }

    /// Read through the runtime's own `defaults`, never the host's — the SimWalk#8 lesson, which the lint rule also holds.
    @Test
    func thereadIsSpelledWithTheRuntimesDefaults() {
        #expect(DeviceLocale.readArguments(udid: "UDID-1", key: "AppleLocale") == ["simctl", "spawn", "UDID-1", "defaults", "read", "-g", "AppleLocale"])
    }

    /// A shell answering the two global keys.
    private static func device(region: String, languages: String) -> (String, [String]) throws -> Shell.Result {
        { _, arguments in
            let output = arguments.last == "AppleLocale" ? region : languages
            return Shell.Result(status: 0, standardOutput: "\(output)\n", standardError: "")
        }
    }
}
