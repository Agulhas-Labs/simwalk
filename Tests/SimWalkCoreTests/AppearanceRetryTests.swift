//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkTestSupport
import Testing

/// SimWalk#26: a screen that refused an appearance the device reported set and did not draw is walked again once the device has been settled, and the second attempt joins the bundle with the record of why.
///
/// These hold the decisions — which screens, what the manifest becomes, what a reader is told — without a simulator; `WalkCommandTests` holds the orchestration around them.
struct AppearanceRetryTests {
    /// Only a screen with a state the appearance check refused is walked again — the refusal a settle can recover — whatever appearance those states asked for and whatever the device was found in.
    ///
    /// A collision over another axis is not, even where its refused states include a `dark` one: `you` refused two dark states whose locales collided, which a reboot cannot cure. Read from the record's structured `refusedOnAppearance`, never from `refusedStates` alone or from the refusal's prose — `weights`' reason reads like `you`'s, and it is the field that tells them apart. Round 1 keyed this on `refusedStates` holding a state in the other appearance, which settled the device for `you` on every walk; this test pinned that as intended, and is rewritten for the narrowed selection.
    @Test
    func onlyAScreenWithAStateRefusedOnAppearanceIsWalkedAgain() {
        let darkInFrench = Walkbook.CaptureState(theme: .dark, locale: "fr_FR")
        let darkInGerman = Walkbook.CaptureState(theme: .dark, locale: "de_DE")
        let collision = "states 'dark-loc_fr_fr' and 'dark-loc_de_de' produced byte-identical screenshots"
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "browse", outcome: .captured, routeTaken: []),
            CaptureManifest.ScreenRecord(id: "progress", outcome: .stateNotApplied(reason: Self.refusal), routeTaken: [], refusedStates: [Self.dark], refusedOnAppearance: [Self.dark]),
            CaptureManifest.ScreenRecord(id: "you", outcome: .stateNotApplied(reason: collision), routeTaken: [], refusedStates: [darkInFrench, darkInGerman]),
            CaptureManifest.ScreenRecord(
                id: "weights",
                outcome: .stateNotApplied(reason: collision),
                routeTaken: [],
                refusedStates: [Self.light, Self.dark],
                refusedOnAppearance: [Self.light, Self.dark]
            ),
        ])

        #expect(AppearanceRetry.screens(toRetryIn: manifest).map(\.id) == ["progress", "weights"])
    }

    /// A state named as refused on appearance is one of the screen's refusals — a record naming another would settle the device over a state the screen never refused.
    @Test
    func arefusalOnAppearanceTheScreenDidNotRefuseIsAProblem() {
        let screens = [
            CaptureManifest.ScreenRecord(id: "progress", outcome: .stateNotApplied(reason: Self.refusal), routeTaken: [], refusedStates: [Self.dark], refusedOnAppearance: [Self.light, Self.dark]),
        ]

        #expect(CaptureManifestValidator.problems(in: Self.manifest(screens: screens)) == [.refusedOnAppearanceNotRefused(screenID: "progress", slug: "light")])
    }

    /// The fold: the retried screen's record and artefacts become the second attempt's, every other screen stays exactly as the first pass filed it, and the manifest records the settle — with the first attempt's verdict, which the bundle no longer holds anywhere else.
    @Test
    func asecondAttemptReplacesOnlyTheRetriedScreenAndTheSettleIsRecorded() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try Self.secondAttempt(in: secondDirectory)
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))

        let folded = try AppearanceRetry.fold(second, into: first, settle: settle)
        let reread = try CaptureBundle.read(at: first.url)

        #expect(reread == folded)
        #expect(reread.manifest.screens.map(\.outcome) == [.captured, .captured])
        #expect(reread.manifest.screens[0].captures.map(\.state) == [Self.light, Self.dark])
        #expect(reread.manifest.screens[1] == first.manifest.screens[1])
        #expect(reread.manifest.walkbookHash == first.manifest.walkbookHash)
        #expect(reread.manifest.appearanceSettle == settle)
        #expect(settle.retried == [
            CaptureManifest.AppearanceSettle.Retry(id: "progress", firstOutcome: .stateNotApplied(reason: Self.refusal), firstRefusedStates: [Self.dark], firstRefusedOnAppearance: [Self.dark]),
        ])
        let dark = try #require(reread.manifest.screens[0].captures.last)
        #expect(FileManager.default.fileExists(atPath: reread.screenshotURL(for: dark).path))
    }

    /// A second attempt that cannot be the same walk — another device — or that recorded other screens than it was sent for is refused before anything is touched: the first attempt's bundle reads exactly as the runner wrote it.
    @Test
    func asecondAttemptThatIsNotTheSameWalkIsRefusedAndTheFirstBundleLeftAsItWas() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try Self.secondAttempt(in: secondDirectory)
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 1, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        var elsewhere = second.manifest
        elsewhere.device.udid = "ANOTHER-DEVICE"
        var otherScreens = second.manifest
        otherScreens.screens[0].id = "browse"

        #expect(throws: AppearanceRetryError.notTheSameWalk(field: "device", first: first.manifest.device.udid, retry: "ANOTHER-DEVICE")) {
            try AppearanceRetry.fold(CaptureBundle(url: second.url, manifest: elsewhere), into: first, settle: settle)
        }
        #expect(throws: AppearanceRetryError.retryRecordedOtherScreens(expected: ["progress"], recorded: ["browse"])) {
            try AppearanceRetry.foldedManifest(first: first.manifest, retry: otherScreens, settle: settle)
        }
        #expect(try CaptureBundle.read(at: first.url) == first)
    }

    /// A settle record is held to what a walk could have written: some screen walked again, each once, each one the manifest records, each for a state its first attempt refused.
    @Test
    func asettleRecordNoWalkCouldHaveWrittenIsAProblem() {
        let refused = CaptureManifest.AppearanceSettle.Retry(id: "nowhere", firstOutcome: .stateNotApplied(reason: Self.refusal), firstRefusedStates: [Self.dark], firstRefusedOnAppearance: [Self.dark])
        let unrefused = CaptureManifest.AppearanceSettle.Retry(id: "browse", firstOutcome: .captured, firstRefusedStates: [], firstRefusedOnAppearance: [])
        let screens = [CaptureManifest.ScreenRecord(id: "browse", outcome: .unreachable(routeTried: []), routeTaken: [])]

        let problems = CaptureManifestValidator.problems(in: Self.manifest(
            screens: screens,
            settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [refused, unrefused, unrefused])
        ))
        let empty = CaptureManifestValidator.problems(in: Self.manifest(
            screens: screens,
            settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [])
        ))

        #expect(problems == [
            .appearanceSettleRetriedUnrecordedScreen(id: "nowhere"),
            .appearanceSettleRetriedTwice(id: "browse", occurrences: 2),
            .appearanceSettleRetryNamesNoRefusal(id: "browse"),
            .appearanceSettleRetryNamesNoRefusal(id: "browse"),
        ])
        #expect(empty == [.appearanceSettleRetriedNothing])
    }

    /// A manifest with no settle is written exactly as before the field existed, and one with a settle reads back as itself.
    @Test
    func thesettleIsAbsentWhenThereWasNoneAndRoundTripsWhenThereWasOne() throws {
        let screens = [CaptureManifest.ScreenRecord(id: "browse", outcome: .unreachable(routeTried: []), routeTaken: [])]
        let plain = Self.manifest(screens: screens)
        let settled = Self.manifest(screens: screens, settle: CaptureManifest.AppearanceSettle(
            appearance: .dark,
            found: .light,
            milliseconds: 31200,
            retried: [CaptureManifest.AppearanceSettle.Retry(id: "browse", firstOutcome: .stateNotApplied(reason: Self.refusal), firstRefusedStates: [Self.dark], firstRefusedOnAppearance: [Self.dark])]
        ))

        let written = try String(decoding: JSONEncoder().encode(plain), as: UTF8.self)

        #expect(!written.contains("appearanceSettle"))
        #expect(try JSONDecoder().decode(CaptureManifest.self, from: JSONEncoder().encode(settled)) == settled)
    }

    /// The answer says why the walk took longer and what each retried screen came to — recovered here — without qualifying a walk whose captures are all honest.
    @Test
    func theanswerNamesTheSettleAndWhatEachRetriedScreenCameTo() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        let folded = try AppearanceRetry.fold(Self.secondAttempt(in: secondDirectory), into: first, settle: settle)

        let answer = CaptureBundleSummary(folded).answer()

        #expect(answer.text.contains("appearance settle: 1 screen had a state refused on appearance — a render that did not show the appearance its state asked for, as a device that reports one appearance and draws the other produces — so the device was set dark, shut down, booted and put back to light (31.2s), and it was walked again:"))
        #expect(answer.text.contains("progress — first refused [dark]; now captured"))
        #expect(!answer.verdict.isQualified)
    }

    /// Review finding 4: a second attempt that keeps less than the first did is not taken.
    ///
    /// The first pass kept `progress`'s light capture and refused its dark one; after the settle the route failed, and folding that in would have dropped a valid light capture and its files for an `unreachable`.
    ///
    /// So the first attempt stands — record and artefacts — and the settle says, on that screen, what the second attempt came to.
    @Test
    func asecondAttemptThatKeepsLessThanTheFirstIsNotTakenAndTheFirstStands() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try CaptureBundleFixture.writeWalk(in: secondDirectory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "progress", outcome: .unreachable(routeTried: []), routeTaken: []),
        ])
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))

        let folded = try AppearanceRetry.fold(second, into: first, settle: settle)
        let reread = try CaptureBundle.read(at: first.url)

        #expect(reread == folded)
        #expect(reread.manifest.screens == first.manifest.screens)
        let light = try #require(reread.manifest.screens[0].captures.first)
        #expect(FileManager.default.fileExists(atPath: reread.screenshotURL(for: light).path))
        let notFolded = try #require(reread.manifest.appearanceSettle?.retried.first?.notFolded)
        #expect(notFolded.contains("its second attempt kept nothing and was unreachable, where the first kept [light]"))
        #expect(CaptureBundleSummary(reread).answer().text.contains("progress — first refused [dark]; its second attempt kept nothing and was unreachable"))
    }

    /// Review finding 3: a settle that stopped short still rebooted — or shut down — the device, so the first attempt's manifest records it, with the step it stopped at, and every record stays the first attempt's.
    @Test
    func asettleThatStoppedShortIsRecordedOnTheFirstAttempt() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.firstAttempt(in: directory)
        var settle = AppearanceRetry.settle(found: .light, milliseconds: 1000, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        settle.settleFailure = "booting it (code=164)"

        try AppearanceRetry.recordUnfolded(settle, in: first)
        let reread = try CaptureBundle.read(at: first.url)

        #expect(reread.manifest.screens == first.manifest.screens)
        #expect(reread.manifest.appearanceSettle == settle)
        let text = CaptureBundleSummary(reread).answer().text
        #expect(text.contains("the settle stopped booting it (code=164) after 1.0s; it was not walked again, and the first attempt stands:"))
        #expect(text.contains("progress — first refused [dark]; its first attempt stands"))
    }

    /// A bundle whose manifest a fold already took away is not written over: its artefacts may be the second attempt's, and the first attempt's record over them would read as a pass.
    @Test
    func anUnfoldedSettleIsNotRecordedOverABundleAFoldBegan() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.firstAttempt(in: directory)
        try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: first.url))

        #expect(throws: CaptureBundleError.self) {
            try AppearanceRetry.recordUnfolded(AppearanceRetry.settle(found: .light, milliseconds: 1, retrying: first.manifest.screens.filter { $0.id == "progress" }), in: first)
        }
        #expect(!FileManager.default.fileExists(atPath: CaptureBundle.manifestURL(in: first.url).path))
    }

    /// Where the settle says a screen kept its first attempt — nothing folded, or that screen's second attempt declined — its record is that first attempt, or the record is nobody's.
    @Test
    func ascreenTheSettleSaysKeptItsFirstAttemptMustCarryIt() {
        let captured = [CaptureManifest.ScreenRecord(id: "progress", outcome: .unreachable(routeTried: []), routeTaken: [])]
        let first = CaptureManifest.AppearanceSettle.Retry(id: "progress", firstOutcome: .stateNotApplied(reason: Self.refusal), firstRefusedStates: [Self.dark], firstRefusedOnAppearance: [Self.dark])
        var declined = first
        declined.notFolded = "its second attempt kept nothing"

        let unfolded = CaptureManifestValidator.problems(in: Self.manifest(
            screens: captured,
            settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [first], secondPassFailure: "no bundle")
        ))
        let notTaken = CaptureManifestValidator.problems(in: Self.manifest(
            screens: captured,
            settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [declined])
        ))
        let taken = CaptureManifestValidator.problems(in: Self.manifest(
            screens: captured,
            settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [first])
        ))

        #expect(unfolded == [.appearanceSettleUnfoldedScreenIsNotItsFirstAttempt(id: "progress")])
        #expect(notTaken == [.appearanceSettleUnfoldedScreenIsNotItsFirstAttempt(id: "progress")])
        #expect(taken.isEmpty)
    }

    /// The round-2 review's finding 2: a fold whose swap fails partway — here the move that brings the second attempt's screen in — is undone, and the first attempt reads exactly as the first pass wrote it, every screen's captures included.
    ///
    /// It used to remove the first manifest and the replaced directory before moving anything in, so one failed move left a bundle with no manifest, and every screen's valid captures unreadable.
    ///
    /// Put back, the manifest takes the settle record again, which is then true: nothing was folded.
    @Test
    func afoldWhoseSwapFailsPartwayPutsTheFirstAttemptBack() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try Self.secondAttempt(in: secondDirectory)
        var settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        let incoming = Self.screenDirectory("progress", in: second.url).path
        let failing = FailingMoves.fileManager { source, _ in source.path == incoming }

        #expect(throws: CaptureBundleError.self) {
            try AppearanceRetry.fold(second, into: first, settle: settle, fileManager: failing)
        }
        #expect(try CaptureBundle.read(at: first.url) == first)
        let light = try #require(first.manifest.screens[0].captures.first)
        #expect(FileManager.default.fileExists(atPath: first.screenshotURL(for: light).path))

        settle.secondPassFailure = "the fold failed and was undone"
        try AppearanceRetry.recordUnfolded(settle, in: first)
        #expect(try CaptureBundle.read(at: first.url).manifest.appearanceSettle == settle)
    }

    /// A folded manifest `finalise` refuses — the scratch bundle lost an artefact after it was read — is undone the same way, after every screen has been swapped.
    @Test
    func afoldWhoseManifestIsRefusedPutsTheFirstAttemptBack() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try Self.secondAttempt(in: secondDirectory)
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        let dark = try #require(second.manifest.screens[0].captures.last)
        try FileManager.default.removeItem(at: second.screenshotURL(for: dark))

        #expect(throws: CaptureBundleError.self) {
            try AppearanceRetry.fold(second, into: first, settle: settle)
        }
        #expect(try CaptureBundle.read(at: first.url) == first)
    }

    /// A fold that fails and cannot be undone either says where the first attempt is: its manifest and the screen directory the fold replaced are set aside in the scratch bundle, laid out as a bundle, for a person to move back — and the first bundle stays without a manifest, refused by name, rather than holding the first attempt's record over a second attempt's pictures.
    @Test
    func afoldThatCannotBeUndoneSaysWhereTheFirstAttemptIsSetAside() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.firstAttempt(in: firstDirectory)
        let second = try Self.secondAttempt(in: secondDirectory)
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 31200, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        let scratch = second.url.path
        // Every move out of the scratch bundle fails: the one bringing the second attempt in, and then the one putting the
        // first attempt's screen back.
        let failing = FailingMoves.fileManager { source, _ in source.path.hasPrefix(scratch) }
        let setAside = CaptureBundleLayout.setAsideDirectory(in: second.url)

        let thrown = try #require(#expect(throws: AppearanceRetryError.self) {
            try AppearanceRetry.fold(second, into: first, settle: settle, fileManager: failing)
        })

        guard case let .foldNotUndone(path, _, _) = thrown else {
            Issue.record("a fold that could not be undone must say where the first attempt is, got \(thrown)")
            return
        }

        #expect(path == setAside.path)
        #expect(thrown.description.contains("set aside at \(setAside.path)"))
        #expect(FileManager.default.fileExists(atPath: CaptureBundle.manifestURL(in: setAside).path))
        #expect(FileManager.default.fileExists(atPath: Self.screenDirectory("progress", in: setAside).path))
        #expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: first.url)
        }
    }

    /// The round-2 review's finding 4: the settle records which of a screen's first refusals were on appearance — the ones it was made for — which the screen's own record stops saying once a fold replaces it.
    ///
    /// Printed where they are not all of the first refusals, and held to what a walk could write: some refusal on appearance, each of them one of the first attempt's refusals.
    @Test
    func thesettleRecordsWhichFirstRefusalsWereOnAppearance() throws {
        let (firstDirectory, secondDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let large = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "xxl")
        let first = try CaptureBundleFixture.writeWalk(in: firstDirectory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "progress",
                outcome: .stateNotApplied(reason: Self.refusal),
                captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Self.light, tree: CaptureBundleFixture.plainScreen())],
                refusedStates: [large, Self.dark],
                refusedOnAppearance: [Self.dark]
            ),
        ])
        let settle = AppearanceRetry.settle(found: .light, milliseconds: 1000, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        let folded = try AppearanceRetry.fold(Self.secondAttempt(in: secondDirectory), into: first, settle: settle)
        var noneOnAppearance = try #require(settle.retried.first)
        noneOnAppearance.firstRefusedOnAppearance = []
        var notRefused = noneOnAppearance
        notRefused.firstRefusedOnAppearance = [Self.lightInEnglish]
        let screens = [CaptureManifest.ScreenRecord(id: "progress", outcome: .unreachable(routeTried: []), routeTaken: [])]
        let problems = { (retry: CaptureManifest.AppearanceSettle.Retry) in
            CaptureManifestValidator.problems(in: Self.manifest(
                screens: screens,
                settle: CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 1, retried: [retry])
            ))
        }

        #expect(settle.retried.first?.firstRefusedOnAppearance == [Self.dark])
        #expect(folded.manifest.appearanceSettle?.retried.first?.firstRefusedOnAppearance == [Self.dark])
        #expect(CaptureBundleSummary(folded).answer().text.contains("progress — first refused [light-dt_xxl, dark] ([dark] on appearance); now captured"))
        #expect(problems(noneOnAppearance) == [.appearanceSettleRetryNamesNoRefusalOnAppearance(id: "progress")])
        #expect(problems(notRefused) == [.appearanceSettleRefusedOnAppearanceNotRefused(id: "progress", slug: Self.lightInEnglish.slug)])
    }

    /// The round-3 review's finding 3: a settle the walk did not make — the device was not its to reboot — is recorded in the manifest with why and the command that makes it, so an `inspect` of the bundle says it a week later, where the walk's answer is gone.
    ///
    /// Held to what a walk could write: a settle not made stopped at no step, walked nothing again and took no time — and every screen it names keeps its first attempt.
    @Test
    func asettleNotMadeIsRecordedWithWhyAndTheCommandThatMakesIt() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.firstAttempt(in: directory)
        var settle = AppearanceRetry.settle(found: .light, milliseconds: 0, retrying: AppearanceRetry.screens(toRetryIn: first.manifest))
        settle.declined = CaptureManifest.AppearanceSettle.Declined(reason: "UDID-1 was already booted and was not named by UDID", command: "xcrun simctl shutdown UDID-1")
        var stoppedToo = settle
        stoppedToo.settleFailure = "booting it (code=164)"
        var walkedToo = settle
        walkedToo.secondPassFailure = "no bundle"
        var tookTimeToo = settle
        tookTimeToo.milliseconds = 4960
        var notFoldedToo = settle
        notFoldedToo.retried[0].notFolded = "kept less than the first attempt"
        let validated = { (settle: CaptureManifest.AppearanceSettle) in
            CaptureManifestValidator.problems(in: Self.manifest(screens: first.manifest.screens, settle: settle))
        }

        try AppearanceRetry.recordUnfolded(settle, in: first)
        let reread = try CaptureBundle.read(at: first.url)

        #expect(reread.manifest.appearanceSettle?.declined == settle.declined)
        #expect(reread.manifest.appearanceSettle?.folded == false)
        #expect(reread.manifest.screens == first.manifest.screens)
        let text = CaptureBundleSummary(reread).answer().text
        #expect(text.contains("and no settle was made: UDID-1 was already booted and was not named by UDID; it was not walked again, and the first attempt stands:"))
        #expect(text.contains("progress — first refused [dark]; its first attempt stands"))
        #expect(text.contains("to settle it, then walk again: xcrun simctl shutdown UDID-1"))
        #expect(validated(stoppedToo) == [.appearanceSettleDeclinedYetMade])
        #expect(validated(walkedToo) == [.appearanceSettleDeclinedYetMade])
        #expect(validated(tookTimeToo) == [.appearanceSettleDeclinedYetMade])
        #expect(validated(notFoldedToo) == [.appearanceSettleDeclinedYetMade])
        #expect(validated(settle).isEmpty)
    }

    static let light = Walkbook.CaptureState(theme: .light)
    static let dark = Walkbook.CaptureState(theme: .dark)
    static let lightInEnglish = Walkbook.CaptureState(theme: .light, locale: "en_GB")
    static var refusal: String {
        "state 'dark' is no darker than 'light' (mean brightness 0.929 against 0.929)"
    }

    /// The first pass on a device that reported `dark` and drew light: `progress` kept its light capture and refused its dark one; `browse` was light-only and captured.
    private static func firstAttempt(in directory: TemporaryDirectory) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "progress",
                outcome: .stateNotApplied(reason: refusal),
                captures: [CaptureBundleFixture.Capture(screenID: "progress", state: light, tree: CaptureBundleFixture.plainScreen())],
                refusedStates: [dark],
                refusedOnAppearance: [dark]
            ),
            CaptureBundleFixture.ScreenSpec(id: "browse", captures: [CaptureBundleFixture.Capture(screenID: "browse", state: light, tree: CaptureBundleFixture.plainScreen())]),
        ])
    }

    /// The second pass over `progress` on the settled device, both states captured.
    private static func secondAttempt(in directory: TemporaryDirectory) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "progress", captures: [
                CaptureBundleFixture.Capture(screenID: "progress", state: light, tree: CaptureBundleFixture.plainScreen()),
                CaptureBundleFixture.Capture(screenID: "progress", state: dark, tree: CaptureBundleFixture.plainScreen()),
            ]),
        ])
    }

    /// One screen's directory inside the bundle at `url`, as the layout derives it.
    private static func screenDirectory(_ screenID: String, in url: URL) -> URL {
        CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.screenDirectory(screenID: screenID), in: url)
    }

    private static func manifest(screens: [CaptureManifest.ScreenRecord], settle: CaptureManifest.AppearanceSettle? = nil) -> CaptureManifest {
        CaptureManifest(
            walkName: "walk",
            appBundleID: "com.example.probe",
            appBuildHash: "a1b2c3d4",
            walkbookHash: "0f1e2d3c",
            device: CaptureManifest.Device(name: "iPhone 17", udid: "UDID-1", osVersion: "27.0"),
            startedAt: Date(timeIntervalSince1970: 1_786_867_200),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_260),
            appearanceSettle: settle,
            screens: screens
        )
    }
}
