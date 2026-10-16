//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// When something sits over or beside a screen, `ScreenIdentifier` must still name the screen shown — and it recognises a presentation only where the tree states one: a node XCUITest types `Alert`, `Sheet` or `Popover`, or a page sheet by the exact shape UIKit gives one.
///
/// Anything else over the screen is read with the screen, which is the documented residual, not a guess (SimWalk#20 round 5, rulings 3, 4 and 6).
///
/// The trees marked *real* are shaped node for node as the runner captured stock apps (`PresentationTreeFixture`); the rest are synthetic, on the same real-shaped screen (`ScreenTreeFixture`). Until round 5 a rule on frames — a layer reaching the screen's centre — read presentations too; the tests that pinned it are rewritten here to pin its absence.
struct ScreenPresentationTests {
    // MARK: Nothing inside the screen's own content is a presentation

    /// A scrolled screen whose tall section, after a header, covers the whole frame: that is the screen's own content, not a layer over it, and the scroll view's identifier answers.
    @Test
    func atallSectionAfterAHeaderInsideTheScrollViewIsTheScreensOwnContent() {
        let scrollView = AXNode(
            type: "ScrollView",
            frame: ScreenTreeFixture.screenFrame,
            identifier: "App.LogScreen",
            children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: -260, width: 402, height: 60), children: [Self.text("This week", y: -240)]),
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: -200, width: 402, height: 1400), children: [Self.text("Monday", y: 132), Self.text("Tuesday", y: 172)]),
            ]
        )
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [scrollView]))

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.LogScreen", source: .content))
    }

    /// A horizontal pager inside an identified collection view — the page on screen covering the frame after the page before it — is the screen's content, whether the pages are cells or plain containers.
    @Test(arguments: ["Cell", "Other"])
    func apagerInsideAnIdentifiedCollectionViewIsTheScreensOwnContent(pageType: String) {
        let pager = AXNode(
            type: "CollectionView",
            frame: ScreenTreeFixture.screenFrame,
            identifier: "App.PagerScreen",
            children: [
                AXNode(type: pageType, frame: AXNode.Frame(x: -402, y: 0, width: 402, height: 874), children: [Self.text("Page one", y: 400)]),
                AXNode(type: pageType, frame: ScreenTreeFixture.screenFrame, children: [Self.text("Page two", y: 400)]),
            ]
        )
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [pager]))

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.PagerScreen", source: .content))
    }

    /// A small header before the identified content is not a screen the content is drawn over.
    @Test
    func contentAfterASmallHeaderIsNotReadAsPresentedOverIt() {
        let header = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 100), children: [Self.text("Summary", y: 60)])
        let tree = ScreenTreeFixture.application(window: [
            AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [header, ScreenTreeFixture.content(identifier: "App.LogScreen", texts: ["Entries"])]),
        ])

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.LogScreen", source: .content))
    }

    // MARK: An overlay with no presentation type is read with the screen (the residual)

    /// A non-modal overlay — a centred HUD, a centred toast, a loading overlay, an empty-state overlay beside a list, a floating button centred in a wrapper, and a sheet-like layer that carries neither a presentation type nor a page sheet's shape — is never a presentation: it is read with the screen, so the screen's own identifier answers and nothing is presented (SimWalk#20 round 4, finding 3 — each of these was read as presented, or not, by where its frame reached).
    @Test(arguments: [
        AXNode(type: "Other", frame: AXNode.Frame(x: 126, y: 362, width: 150, height: 150), label: "Saving", children: [
            AXNode(type: "ActivityIndicator", frame: AXNode.Frame(x: 181, y: 400, width: 40, height: 40), label: "In progress"),
        ]),
        AXNode(type: "Other", frame: AXNode.Frame(x: 51, y: 417, width: 300, height: 40), children: [Self.text("Copied to clipboard", y: 429)]),
        AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "ActivityIndicator", frame: AXNode.Frame(x: 181, y: 417, width: 40, height: 40), label: "Loading"),
        ]),
        AXNode(type: "Other", frame: AXNode.Frame(x: 40, y: 300, width: 322, height: 274), children: [Self.text("No entries yet", y: 420)]),
        AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 173, y: 409, width: 56, height: 56), label: "Add entry"),
        ]),
        AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 60, width: 402, height: 814), children: [
            AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame),
            ScreenTreeFixture.navigationBar(identifier: "Edit Profile", back: "Cancel"),
            ScreenTreeFixture.content(identifier: nil, texts: ["Name"]),
        ]),
    ])
    func anoverlayWithNoPresentationTypeIsReadWithTheScreen(overlay: AXNode) {
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.LogScreen", texts: ["Entries"]), overlays: [overlay])

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.LogScreen", source: .content))
    }

    /// A toast in a window of its own is not a presentation — and its window never names the screen, even when the toast carries an identifier and the screen does not.
    @Test
    func atoastWindowIsNeitherAPresentationNorTheScreensIdentifier() {
        let toast = PresentationTreeFixture.window(AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 60, width: 370, height: 50),
            identifier: "App.Toast",
            children: [Self.text("Saved", y: 76)]
        ))
        let identified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.LogScreen", texts: ["Entries"]), windows: [toast])
        let unidentified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: nil, texts: ["Entries"]), windows: [toast])

        #expect(ScreenIdentifier(of: identified) == ScreenIdentifier(value: "App.LogScreen", source: .content))
        #expect(ScreenIdentifier.presentation(in: unidentified) == nil)
        #expect(ScreenIdentifier(of: unidentified) == nil)
    }

    // MARK: The app's window is the first; the keyboard's are chrome

    /// The app's window is the first window in tree order, whatever it holds: a screen of images with no text, under an identified scroll view, is still the screen, and a later window holding text and an identifier never becomes it (SimWalk#20 round 4, finding 4 — the first window *holding text* was the app's until then).
    @Test
    func theappsWindowIsTheFirstEvenWhenALaterOneHoldsTheText() {
        let gallery = AXNode(type: "ScrollView", frame: ScreenTreeFixture.screenFrame, identifier: "App.GalleryScreen", children: [
            AXNode(type: "Image", frame: AXNode.Frame(x: 0, y: 100, width: 201, height: 201), identifier: "photo-1"),
            AXNode(type: "Image", frame: AXNode.Frame(x: 201, y: 100, width: 201, height: 201), identifier: "photo-2"),
        ])
        let banner = PresentationTreeFixture.window(AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 60, width: 370, height: 50),
            identifier: "App.Banner",
            children: [Self.text("Synced", y: 76)]
        ))
        let tree = ScreenTreeFixture.application(window: [gallery], windows: [banner])

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.GalleryScreen", source: .content))
    }

    /// A full-screen keyboard window whose keys carry identifiers is neither a presentation nor read: the screen's identifier answers, never a key's.
    @Test
    func akeyboardWindowIsChromeAndItsKeysNeverAnswer() {
        let keys = ["q", "w", "e"].enumerated().map { index, key in
            AXNode(type: "Key", frame: AXNode.Frame(x: 4 + Double(index) * 40, y: 590, width: 39, height: 54), label: key, identifier: key)
        }
        let keyboard = AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "Keyboard", frame: ScreenTreeFixture.screenFrame, children: [AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: keys)]),
        ])
        let identified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.SearchScreen", texts: ["Results"]), windows: [keyboard])
        let unidentified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: nil, texts: ["Results"]), windows: [keyboard])

        #expect(ScreenIdentifier(of: identified) == ScreenIdentifier(value: "App.SearchScreen", source: .content))
        #expect(ScreenIdentifier(of: unidentified) == nil)
    }

    /// A window holding the keyboard — named, or the raw `Type19` of an older bundle — is chrome and never searched: a popover it shows beside the keys, such as a key's accent variants, is not a presentation over the screen.
    @Test(arguments: ["Keyboard", "Type19"])
    func apopoverInAKeyboardsWindowIsNotAPresentation(keyboardType: String) {
        let variants = AXNode(type: "Popover", frame: AXNode.Frame(x: 4, y: 520, width: 200, height: 60), identifier: "KeyVariants", children: [
            AXNode(type: "Key", frame: AXNode.Frame(x: 8, y: 530, width: 39, height: 44), label: "é"),
        ])
        let window = PresentationTreeFixture.window(AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 520, width: 402, height: 354), children: [
            AXNode(type: keyboardType, frame: AXNode.Frame(x: 0, y: 583, width: 402, height: 233), children: [
                AXNode(type: "Key", frame: AXNode.Frame(x: 4, y: 590, width: 39, height: 54), label: "e"),
            ]),
            variants,
        ]))
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.SearchScreen", texts: ["Results"]), windows: [window])

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.SearchScreen", source: .content))
    }

    /// *Real*: the keyboard as two windows after the app's — the input host, then the predictions bar and the keys — answered its predictions bar's `SystemInputAssistantView` on every real capture with the keyboard up, before round 4.
    ///
    /// It is chrome: the screen's identifier answers, or none.
    @Test
    func therealKeyboardsWindowsNeverAnswer() {
        let identified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.SearchScreen", texts: ["Results"]), windows: PresentationTreeFixture.keyboardWindows())
        let unidentified = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: nil, texts: ["Results"]), windows: PresentationTreeFixture.keyboardWindows())

        #expect(ScreenIdentifier(of: identified) == ScreenIdentifier(value: "App.SearchScreen", source: .content))
        #expect(ScreenIdentifier.presentation(in: unidentified) == nil)
        #expect(ScreenIdentifier(of: unidentified) == nil)
    }

    /// *Real*: on a keyboard's first use its window holds the continuous-path introduction — text and a button, no keyboard node — under UIKit's class name: neither a presentation nor an identifier, on any screen size, because nothing in it carries a presentation type.
    @Test
    func therealKeyboardIntroductionIsNeitherAPresentationNorAnIdentifier() {
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: nil, texts: ["Results"]), windows: PresentationTreeFixture.keyboardIntroductionWindows())

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree) == nil)
    }

    // MARK: A presentation is told by its type

    /// A node XCUITest types as a presentation — an alert, an action sheet, a popover, or the raw `Type18` an older bundle holds for one — is the presentation wherever it sits, and its own identifier answers over the covered screen's, marked presented.
    @Test(arguments: [("Alert", "Alert"), ("Sheet", "Sheet"), ("Popover", "Popover"), ("Type18", "Popover")])
    func atypedPresentationIsThePresentationAndItsIdentifierAnswers(type: String, kind: String) {
        let dialog = AXNode(type: type, frame: AXNode.Frame(x: 36, y: 340, width: 330, height: 190), identifier: "App.ConfirmDialog", children: [
            Self.text("Discard changes?", y: 360),
        ])
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.SettingsScreen", texts: ["Account"]), presented: [dialog])

        #expect(ScreenIdentifier.presentation(in: tree)?.kind == kind)
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.ConfirmDialog", source: .content, isPresented: true))
    }

    /// *Real*: a confirmation dialog shown as a popover — the dismiss region, then a popover node holding a `Sheet`, the covered screen gone — is the presented popover, whether an older bundle holds it as `Type18` or the runner names it, and nothing on it identifies it.
    @Test(arguments: ["Type18", "Popover"])
    func therealPopoverDialogIsThePresentedPopoverUnidentified(popoverType: String) {
        let tree = ScreenTreeFixture.application(
            window: [PresentationTreeFixture.popoverDialog(message: "Discard this new contact?", action: "Discard Changes", popoverType: popoverType)],
            windows: PresentationTreeFixture.keyboardWindows()
        )

        #expect(ScreenIdentifier.presentation(in: tree)?.kind == "Popover")
        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == nil)
    }

    /// The topmost presentation is the last in tree order: an alert in a window after the app's, over a page sheet in the app's window, is the one read.
    @Test
    func thelastPresentationInTreeOrderIsTheOneRead() {
        let tree = ScreenTreeFixture.application(
            window: [PresentationTreeFixture.pageSheet(bar: nil, content: ScreenTreeFixture.content(identifier: "App.EditorScreen", texts: ["Title"]))],
            windows: [PresentationTreeFixture.window(ScreenTreeFixture.alert(title: "Discard?", identifier: "App.DiscardAlert"))]
        )

        #expect(ScreenIdentifier.presentation(in: tree)?.kind == "Alert")
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.DiscardAlert", source: .content, isPresented: true))
    }

    /// Inside a presentation, a framework's region answers no more than it would on the screen: a named system identifier, an underscore-private one and a mangled class name are each passed over for the sheet's own identifier.
    @Test(arguments: ["PopoverDismissRegion", "_UIDropShadowView", "_TtC5UIKit17UISheetHostView"])
    func aframeworksIdentifierNeverAnswersInsideAPresentation(framework: String) {
        let sheetContent = AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, identifier: framework, children: [AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame)]),
            ScreenTreeFixture.content(identifier: "EditorScreen.Identifiers_screen", texts: ["New entry"]),
        ])
        let tree = ScreenTreeFixture.app(
            content: ScreenTreeFixture.content(identifier: "ListScreen.Identifiers_screen", texts: ["Entries"]),
            presented: [PresentationTreeFixture.pageSheet(bar: nil, content: sheetContent)]
        )

        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "EditorScreen.Identifiers_screen", source: .content, isPresented: true))
    }

    // MARK: A page sheet is told by its real shape

    /// *Real*: a page sheet takes the covered screen out of the tree, so the sheet is all there is to read — its fields' own identifiers never answer, its bar's title does only when asked for, the keyboard its first field raised is chrome — and it **is** presented, told by its dimming view reaching past every edge and its `Sheet Grabber` (SimWalk#20 round 4, finding 7: this read not presented, against the property's own doc).
    @Test
    func therealPageSheetIsPresentedAndAnswersItsOwnBarsTitleOnlyWhenAsked() {
        let tree = ScreenTreeFixture.application(
            window: [PresentationTreeFixture.pageSheet(
                bar: ScreenTreeFixture.navigationBar(identifier: "New Contact", back: "Cancel"),
                content: PresentationTreeFixture.formContent(fields: ["First name", "Last name"])
            )],
            windows: PresentationTreeFixture.keyboardWindows()
        )

        #expect(ScreenIdentifier.presentation(in: tree)?.kind == "page sheet")
        #expect(ScreenIdentifier(of: tree) == nil)
        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "New Contact", source: .navigationBar, isPresented: true))
    }

    /// The page-sheet shape is matched exactly, so a near miss over an identified screen is no presentation and the screen answers: no grabber, a grabber labelled otherwise, a dimming view that stops at the screen's edges rather than reaching past them, and a grabber's container drawn *before* the dimming view rather than after it.
    @Test(arguments: PageSheetNearMiss.allCases)
    func anearMissOfThePageSheetShapeIsNotAPresentation(nearMiss: PageSheetNearMiss) {
        let tree = ScreenTreeFixture.app(content: ScreenTreeFixture.content(identifier: "App.ListScreen", texts: ["Entries"]), presented: [nearMiss.layer])

        #expect(ScreenIdentifier.presentation(in: tree) == nil)
        #expect(ScreenIdentifier(of: tree) == ScreenIdentifier(value: "App.ListScreen", source: .content))
    }

    private static func text(_ label: String, y: Double) -> AXNode {
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: y, width: 300, height: 16), label: label)
    }
}
