//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// The layers a real capture holds over or beside a screen — the keyboard, a page sheet, a popover — shaped node for node as the runner captured them from stock apps on an iOS 26.5 simulator, with the text shortened.
///
/// What the real captures showed, and what these keep: the keyboard is two windows after the app's, never a node in the app's own; a page sheet and a popover sit inside the app's window, after a dimming view or a dismiss barrier, **with the covered screen gone from the tree**; and the runner that took them wrote the types it did not yet spell out by XCUITest's raw code — the keyboard `Type19`, its keys `Type20`, a popover `Type18` — which is how every bundle from before it named every type holds them.
public struct PresentationTreeFixture {
    /// The keyboard as it stands once it has been used: a window holding the input view's empty host, then a window holding the typing-predictions bar, the keys under a keyboard node — the shift and return keys buttons, the rest keys, several carrying identifiers — and the emoji and dictation buttons.
    public static func keyboardWindows() -> [AXNode] {
        let keys = ["q", "w", "e", "r", "t", "y"].enumerated().map { index, key in
            AXNode(type: "Type20", frame: AXNode.Frame(x: 4 + Double(index) * 40, y: 590, width: 39, height: 54), label: key)
        } + [
            AXNode(type: "Button", frame: AXNode.Frame(x: 4, y: 698, width: 51, height: 54), label: "shift", identifier: "shift"),
            AXNode(type: "Type20", frame: AXNode.Frame(x: 348, y: 698, width: 51, height: 54), label: "delete", identifier: "delete"),
            AXNode(type: "Type20", frame: AXNode.Frame(x: 103, y: 752, width: 197, height: 54), label: " ", identifier: "space"),
            AXNode(type: "Button", frame: AXNode.Frame(x: 300, y: 752, width: 99, height: 54), label: "return", identifier: "Return"),
        ]
        let keyboard = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335),
            children: [
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 44),
                    identifier: "SystemInputAssistantView",
                    children: [
                        AXNode(
                            type: "Other",
                            frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 44),
                            identifier: "CenterPageView",
                            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 44), label: "Typing Predictions")]
                        ),
                    ]
                ),
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 0, y: 583, width: 402, height: 233),
                    children: [
                        AXNode(
                            type: "Type19",
                            frame: AXNode.Frame(x: 0, y: 583, width: 402, height: 233),
                            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 583, width: 402, height: 233), identifier: "UIKeyboardLayoutStar Preview", children: keys)]
                        ),
                    ]
                ),
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 0, y: 583, width: 402, height: 291),
                    children: [
                        AXNode(type: "Button", frame: AXNode.Frame(x: 8, y: 805, width: 68, height: 68), label: "Emoji"),
                        AXNode(type: "Button", frame: AXNode.Frame(x: 325, y: 805, width: 68, height: 68), label: "Dictate", identifier: "dictation"),
                    ]
                ),
            ]
        )
        return [inputHostWindow(), window(keyboard)]
    }

    /// The keyboard on its first use: the same input host, then — in place of the keys — the continuous-path introduction, its text and its `Continue` button, under an identifier that is UIKit's class name.
    public static func keyboardIntroductionWindows() -> [AXNode] {
        let introduction = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335),
            children: [
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335),
                    identifier: "UIContinuousPathIntroductionView",
                    children: [
                        AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335)),
                        AXNode(
                            type: "Other",
                            frame: AXNode.Frame(x: 41, y: 539, width: 320, height: 301),
                            children: [
                                AXNode(
                                    type: "ScrollView",
                                    frame: AXNode.Frame(x: 41, y: 539, width: 320, height: 253),
                                    children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 41, y: 737, width: 320, height: 46), label: "Speed up your typing")]
                                ),
                                AXNode(type: "Button", frame: AXNode.Frame(x: 89, y: 819, width: 224, height: 21), label: "Continue"),
                            ]
                        ),
                    ]
                ),
            ]
        )
        return [inputHostWindow(), window(introduction)]
    }

    /// A page sheet as the app's window holds one: a dimming view reaching a screen past every edge, then the sheet's container — its grabber, then a container holding `bar` and `content` — under 62 pt of the screen it covers, which is no longer in the tree.
    public static func pageSheet(bar: AXNode?, content: AXNode) -> AXNode {
        AXNode(
            type: "Other",
            frame: ScreenTreeFixture.screenFrame,
            children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: -402, y: -874, width: 1206, height: 2622)),
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 812),
                    children: [
                        AXNode(type: "Button", frame: AXNode.Frame(x: 163, y: 57, width: 76, height: 25), label: "Sheet Grabber", value: "Expanded"),
                        AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 812), children: [bar].compactMap(\.self) + [content]),
                    ]
                ),
            ]
        )
    }

    /// A sheet's content as a real one sits: a table of cells whose text fields carry their own identifiers, and nothing identifying the sheet itself.
    public static func formContent(fields: [String]) -> AXNode {
        AXNode(
            type: "Table",
            frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 812),
            children: fields.enumerated().map { index, field in
                AXNode(
                    type: "Cell",
                    frame: AXNode.Frame(x: 20, y: 390 + Double(index) * 53, width: 362, height: 53),
                    children: [AXNode(type: "TextField", frame: AXNode.Frame(x: 36, y: 406 + Double(index) * 53, width: 330, height: 22), label: field, identifier: field)]
                )
            }
        )
    }

    /// A confirmation dialog shown as a popover, as the app's window holds one: a full-screen barrier XCUITest identifies `PopoverDismissRegion`, then the popover node — typed `popoverType`, the raw `Type18` the real capture holds or the `Popover` the runner now writes — holding a `Sheet` with `message` and one `action` button, then the popover's empty backing — the covered screen gone from the tree.
    public static func popoverDialog(message: String, action: String, popoverType: String = "Type18") -> AXNode {
        let popoverFrame = AXNode.Frame(x: 10, y: 72, width: 240, height: 168)
        return AXNode(
            type: "Other",
            frame: ScreenTreeFixture.screenFrame,
            children: [
                AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, label: "dismiss pop-up", identifier: "PopoverDismissRegion"),
                AXNode(
                    type: popoverType,
                    frame: popoverFrame,
                    children: [
                        AXNode(
                            type: "Other",
                            frame: popoverFrame,
                            children: [
                                AXNode(
                                    type: "Sheet",
                                    frame: popoverFrame,
                                    label: message,
                                    children: [
                                        AXNode(type: "ScrollView", frame: AXNode.Frame(x: 10, y: 72, width: 240, height: 88), children: [
                                            AXNode(type: "StaticText", frame: AXNode.Frame(x: 40, y: 94, width: 180, height: 64), label: message),
                                        ]),
                                        AXNode(type: "ScrollView", frame: AXNode.Frame(x: 10, y: 160, width: 240, height: 80), children: [
                                            AXNode(type: "Button", frame: AXNode.Frame(x: 26, y: 176, width: 208, height: 48), label: action),
                                        ]),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
                AXNode(type: "Other", frame: popoverFrame, children: [AXNode(type: "Other", frame: popoverFrame)]),
            ]
        )
    }

    /// A window holding one full-screen layer over `content`, as every window after the app's is shaped.
    public static func window(_ content: AXNode) -> AXNode {
        AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, children: [AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [content])])
    }

    /// The window holding the keyboard's input host: an empty full-screen view, then the host itself, childless and identified `inputView`.
    private static func inputHostWindow() -> AXNode {
        AXNode(type: "Window", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
                AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame),
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335), children: [
                    AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 539, width: 402, height: 335), identifier: "inputView"),
                ]),
            ]),
        ])
    }
}
