//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Apple's accessibility audit recorded per state (E1a): the opt-in, the record, the manifest entry and the answer's line.
struct AppleAuditTests {
    private static func walkbookJSON(_ extra: String) -> Data {
        Data(#"{"name":"w","appBundleID":"x.y"\#(extra),"screens":[{"id":"a","route":[{"tab":{"label":"A"}}],"states":[{"theme":"light"}]}]}"#.utf8)
    }

    @Test(arguments: [(#","appleAudit":true"#, true as Bool?), (#","appleAudit":false"#, nil as Bool?), ("", nil as Bool?)])
    func theWalkbookKeyDecodesTrueFalseAndAbsent(extra: String, expected: Bool?) throws {
        let walkbook = try WalkbookLoader.load(from: Self.walkbookJSON(extra), source: "t")

        #expect(walkbook.appleAudit == expected)
    }

    @Test
    func falseIsTheSameAsAbsentAndHashesTheSame() throws {
        let off = try WalkbookLoader.load(from: Self.walkbookJSON(#","appleAudit":false"#), source: "t")
        let absent = try WalkbookLoader.load(from: Self.walkbookJSON(""), source: "t")

        #expect(off.appleAudit == nil)
        #expect(try WalkbookIdentity.hash(of: off) == WalkbookIdentity.hash(of: absent))
    }

    @Test
    func aNonBooleanKeyIsRefused() {
        #expect(throws: (any Error).self) {
            try WalkbookLoader.load(from: Self.walkbookJSON(#","appleAudit":"yes""#), source: "t")
        }
    }

    @Test
    func aMisspelledKeyIsStillRefusedNamingTheRealOne() throws {
        let error = try #require(throws: (any Error).self) {
            try WalkbookLoader.load(from: Self.walkbookJSON(#","appleAudt":true"#), source: "t")
        }

        #expect("\(error)".contains("appleAudit"))
    }

    @Test
    func anAbsentKeyLeavesTheWalkbookHashUnchanged() throws {
        let plain = try WalkbookLoader.load(from: Self.walkbookJSON(""), source: "t")
        let encoded = try String(decoding: JSONEncoder().encode(plain), as: UTF8.self)

        #expect(!encoded.contains("appleAudit"))
    }

    @Test(arguments: [(true, false, true), (false, true, true), (false, false, false)])
    func theFlagOrTheKeyTurnsTheWalkOn(flag: Bool, key: Bool, expected: Bool) {
        let walkbook = Walkbook(name: "w", appBundleID: "x.y", screens: [], appleAudit: key ? true : nil)
        let environment = flag ? [AppleAuditOptIn.environmentKey: AppleAuditOptIn.walkWideValue] : [:]

        #expect(AppleAuditOptIn.records(walkbook, in: environment) == expected)
        #expect(AppleAuditOptIn.hostEnvironmentKey == "TEST_RUNNER_" + AppleAuditOptIn.environmentKey)
    }

    @Test
    func theRecordRoundTripsWithSortedKeys() throws {
        let record = AppleAuditRecord(
            milliseconds: 1982,
            error: nil,
            issues: [
                AppleAuditRecord.Issue(
                    type: "contrast",
                    compactDescription: "Contrast failed",
                    detailedDescription: "Text is too faint",
                    element: AppleAuditRecord.Element(type: "StaticText", identifier: "title", label: "Steps", frame: AXNode.Frame(x: 1, y: 2, width: 3, height: 4))
                ),
                AppleAuditRecord.Issue(type: AppleAuditRecord.typeName(known: nil, raw: 1 << 40), compactDescription: "c", detailedDescription: "d"),
            ]
        )

        let data = try AppleAuditRecord.encoder().encode(record)

        #expect(try JSONDecoder().decode(AppleAuditRecord.self, from: data) == record)
        #expect(try AppleAuditRecord.encoder().encode(record) == data)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""type":"unknown(1099511627776)""#))
        #expect(try #require(text.range(of: "compactDescription")?.lowerBound) < #require(text.range(of: "detailedDescription")?.lowerBound))
        #expect(AppleAuditRecord.typeName(known: "trait", raw: 1) == "trait")
    }

    @Test
    func theElementsReadMarkerRoundTripsAndAbsenceDecodesAsNil() throws {
        let marked = AppleAuditRecord(milliseconds: 1, elementsRead: true)
        let data = try AppleAuditRecord.encoder().encode(marked)
        let bare = try AppleAuditRecord.encoder().encode(AppleAuditRecord(milliseconds: 1))

        #expect(String(decoding: data, as: UTF8.self).contains(#""elementsRead":true"#))
        #expect(try JSONDecoder().decode(AppleAuditRecord.self, from: data) == marked)
        #expect(!String(decoding: bare, as: UTF8.self).contains("elementsRead"))
        #expect(try JSONDecoder().decode(AppleAuditRecord.self, from: bare).elementsRead == nil)
    }

    @Test
    func anIssueDecodesWithElementUnreadableWithElementOrWithNeither() throws {
        func decode(_ extra: String) throws -> AppleAuditRecord.Issue {
            let json = #"{"compactDescription":"c","detailedDescription":"d","type":"contrast"\#(extra)}"#
            return try JSONDecoder().decode(AppleAuditRecord.Issue.self, from: Data(json.utf8))
        }

        let unreadable = try decode(#","elementUnreadable":"gone""#)
        #expect(unreadable.elementUnreadable == "gone")
        #expect(unreadable.element == nil)

        let neither = try decode("")
        #expect(neither.elementUnreadable == nil)
        #expect(neither.element == nil)

        let named = try decode(#","element":{"frame":{"height":4,"width":3,"x":1,"y":2},"identifier":"i","label":"l","type":"Button"}"#)
        #expect(named.element?.label == "l")
        #expect(named.elementUnreadable == nil)

        let record = AppleAuditRecord(milliseconds: 1, issues: [unreadable])
        let data = try AppleAuditRecord.encoder().encode(record)
        #expect(String(decoding: data, as: UTF8.self).contains(#""elementUnreadable":"gone""#))
        #expect(try JSONDecoder().decode(AppleAuditRecord.self, from: data) == record)
    }

    @Test
    func theLayoutPathIsPerStateAndTheEntryIsDerivedFromIt() {
        let record = AppleAuditRecord(milliseconds: 5, error: "boom")
        let capture = CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), appleAudit: record)

        #expect(capture.appleAudit?.path == "screens/today/light/apple-audit.json")
        #expect(capture.appleAudit?.path == CaptureBundleLayout.appleAuditPath(screenID: "today", stateSlug: "light"))
        #expect(capture.appleAudit?.failed == true)
        #expect(capture.appleAudit?.issueCount == 0)
    }

    @Test
    func aManifestWithAndWithoutTheKeyDecodes() throws {
        let audited = CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), appleAudit: AppleAuditRecord(milliseconds: 1500))
        let plain = CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .dark))

        let decoded = try [audited, plain].map { try CaptureBundle.decoder().decode(CaptureManifest.StateCapture.self, from: CaptureBundle.encoder().encode($0)) }

        #expect(decoded == [audited, plain])
        #expect(decoded[1].appleAudit == nil)
        let encodedPlain = try String(decoding: CaptureBundle.encoder().encode(plain), as: UTF8.self)
        #expect(!encodedPlain.contains("appleAudit"))
    }

    @Test
    func theAnswerLineIsAbsentWhenNothingWasAudited() {
        #expect(CaptureBundleSummary.appleAuditLines(CaptureBundleTests.manifest()).isEmpty)
    }

    @Test
    func theAnswerLineCountsStatesTimingsIssuesAndFailures() {
        func issue(_ type: String) -> AppleAuditRecord.Issue {
            AppleAuditRecord.Issue(type: type, compactDescription: "c", detailedDescription: "d")
        }
        func capture(_ screen: String, _ record: AppleAuditRecord?) -> CaptureManifest.StateCapture {
            CaptureManifest.StateCapture(screenID: screen, state: Walkbook.CaptureState(theme: .light), appleAudit: record)
        }
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [], captures: [
                capture("a", AppleAuditRecord(milliseconds: 1800, issues: [issue("contrast"), issue("trait")])),
                capture("a2", AppleAuditRecord(milliseconds: 2000)),
            ]),
            CaptureManifest.ScreenRecord(id: "b", outcome: .captured, routeTaken: [], captures: [
                capture("b", AppleAuditRecord(milliseconds: 6500, error: "timed out")),
                capture("c", nil),
            ]),
        ]

        let lines = CaptureBundleSummary.appleAuditLines(manifest)

        #expect(lines == ["apple audit: 3 states, p50 2.0 s, max 6.5 s — opt-in (appleAudit / --apple-audit); 2 issues recorded, 1 failed"])
    }

    private static func manifest(auditing records: [AppleAuditRecord]) -> CaptureManifest {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [], captures: records.enumerated().map { index, record in
                CaptureManifest.StateCapture(screenID: "a\(index)", state: Walkbook.CaptureState(theme: .light), appleAudit: record)
            }),
        ]
        return manifest
    }

    @Test
    func theAnswerLineSaysOneStateAndOneIssueInTheSingular() {
        let issue = AppleAuditRecord.Issue(type: "contrast", compactDescription: "c", detailedDescription: "d")
        let lines = CaptureBundleSummary.appleAuditLines(Self.manifest(auditing: [AppleAuditRecord(milliseconds: 1200, issues: [issue])]))

        #expect(lines == ["apple audit: 1 state, p50 1.2 s, max 1.2 s — opt-in (appleAudit / --apple-audit); 1 issue recorded"])
    }

    @Test
    func theAnswerLineStatesNoTimingsWhenEveryAuditFailed() {
        let records = (0 ..< 3).map { _ in AppleAuditRecord(milliseconds: 9000, error: "timed out") }
        let lines = CaptureBundleSummary.appleAuditLines(Self.manifest(auditing: records))

        #expect(lines == ["apple audit: 3 states asked, none completed (3 failed) — opt-in (appleAudit / --apple-audit)"])
    }

    /// SimWalk#173: XCTest's audit timeout is told by its domain and code, so a different code or domain under the same message is not one.
    @Test(arguments: [
        (#"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-56 "Audit failed to complete in time" UserInfo={NSLocalizedDescription=Audit failed to complete in time}"#, true),
        (#"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-5 "Audit failed to complete in time""#, false),
        (#"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-560 "Audit failed to complete in time""#, false),
        (#"Error Domain=NSCocoaErrorDomain Code=-56 "Audit failed to complete in time""#, false),
        ("Audit failed to complete in time", false),
    ])
    func aTimeoutIsXCTestsAuditDomainWithCodeMinus56(error: String, timedOut: Bool) {
        #expect(AppleAuditRecord(milliseconds: 15009, error: error).timedOut == timedOut)
    }

    @Test
    func aRecordThatReturnedIsNotATimeout() {
        #expect(!AppleAuditRecord(milliseconds: 2000).timedOut)
    }

    /// SimWalk#190: a state's directory reads back as the screen slug and state slug it was derived from, and a path `stateDirectory` cannot derive reads as no state.
    @Test
    func aStateDirectoryReadsBackAsTheScreenAndStateItWasDerivedFrom() {
        let slug = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "XXL", locale: "fr-FR").slug
        let derived = CaptureBundleLayout.stateDirectory(screenID: "Progress Tab", stateSlug: slug)

        let state = CaptureBundleLayout.state(atStateDirectory: derived)

        #expect(state.map { [$0.screenSlug, $0.stateSlug] } == [CaptureBundleLayout.screenSlug("Progress Tab"), slug])
        #expect(state.map { CaptureBundleLayout.stateDirectory(screenID: $0.screenSlug, stateSlug: $0.stateSlug) } == derived)
        let screen = CaptureBundleLayout.screenDirectory(screenID: "progress")
        for underived in [screen, "\(screen)/", "\(derived)/light", "x\(derived)", derived.replacingOccurrences(of: "progress_tab", with: "Progress Tab")] {
            #expect(CaptureBundleLayout.state(atStateDirectory: underived) == nil, "\(underived)")
        }
    }

    /// SimWalk#190: with no manifest, the timeouts are read from the records on disk, in path order, a returned audit and an unreadable record left out.
    @Test
    func theTimeoutsOfABundleWithNoManifestAreReadFromItsRecords() throws {
        let directory = try TemporaryDirectory()
        let timedOut = AppleAuditRecord(milliseconds: 15009, error: #"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-56 "Audit failed to complete in time""#)
        let capture = { (screen: String, theme: Walkbook.Theme, audit: AppleAuditRecord) in
            CaptureBundleFixture.Capture(screenID: screen, state: Walkbook.CaptureState(theme: theme), tree: CaptureBundleFixture.plainScreen(), appleAudit: audit)
        }
        let screens = [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [capture("today", .light, timedOut)]),
            CaptureBundleFixture.ScreenSpec(id: "browse", captures: [capture("browse", .light, AppleAuditRecord(milliseconds: 2000)), capture("browse", .dark, timedOut)]),
        ]
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: screens)
        try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: bundle.url))
        let malformed = CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.appleAuditPath(screenID: "settings", stateSlug: "light"), in: bundle.url)
        try FileManager.default.createDirectory(at: malformed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: malformed)

        let timeouts = AppleAuditScan.timeouts(recordedIn: bundle.url)

        #expect(timeouts.map { "\($0.screenID) \($0.stateSlug)" } == ["browse dark", "today light"])
        #expect(timeouts.map(\.reason) == ["Audit failed to complete in time", "Audit failed to complete in time"])
    }
}
