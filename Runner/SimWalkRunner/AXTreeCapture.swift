//
// Copyright © Agulhas Labs
//

import SimWalkCore
import XCTest

/// Turns XCUITest's element snapshot into the `AXNode` tree a capture bundle carries.
///
/// `snapshot()` is one round trip for the whole hierarchy, where walking `XCUIElement` queries costs an IPC call per element — on a screen with 400 elements that is the difference between a capture and a stall. It is also the *typed* form of what `debugDescription` prints, so nothing has to be parsed back out of a string.
struct AXTreeCapture {
    /// The app's current screen as a tree — or, for any other element, that element and everything its own snapshot holds.
    ///
    /// `@MainActor` because `snapshot()` is: XCUITest hands back a non-`Sendable` snapshot from the main actor, and the capture has to stay there to read it rather than smuggle it across.
    @MainActor
    static func tree(of element: XCUIElement) throws -> AXNode {
        try node(from: element.snapshot())
    }

    /// One element's snapshot as a childless node — its type, frame, label, identifier and whether it is enabled — for the core to find it in a tree read beside it.
    ///
    /// From a snapshot, not the live element: each property of a live element is a query of its own, and one whose match has gone since the last is recorded as a test failure (SimWalk#47).
    @MainActor
    static func node(of snapshot: XCUIElementSnapshot) -> AXNode {
        AXNode(
            type: name(of: snapshot.elementType),
            frame: AXNode.Frame(
                x: Double(snapshot.frame.origin.x),
                y: Double(snapshot.frame.origin.y),
                width: Double(snapshot.frame.size.width),
                height: Double(snapshot.frame.size.height)
            ),
            label: snapshot.label.isEmpty ? nil : snapshot.label,
            identifier: snapshot.identifier.isEmpty ? nil : snapshot.identifier,
            isEnabled: snapshot.isEnabled
        )
    }

    @MainActor
    private static func node(from snapshot: XCUIElementSnapshot) -> AXNode {
        AXNode(
            type: name(of: snapshot.elementType),
            frame: AXNode.Frame(
                x: Double(snapshot.frame.origin.x),
                y: Double(snapshot.frame.origin.y),
                width: Double(snapshot.frame.size.width),
                height: Double(snapshot.frame.size.height)
            ),
            // Empty is not absent: an element with no label should read as having none, rather than as
            // carrying an empty string a differ would then have to special-case.
            label: snapshot.label.isEmpty ? nil : snapshot.label,
            identifier: snapshot.identifier.isEmpty ? nil : snapshot.identifier,
            value: (snapshot.value as? String).flatMap { $0.isEmpty ? nil : $0 },
            // The two traits that separate one row from another row drawn the same way. Without them a
            // selected pill and its four unselected siblings serialise identically, so a bundle audit
            // cannot tell an app that never exposes selection from a capture that never recorded it —
            // which is how a real §17 defect came to be filed against an app doing neither (SimWalk#2).
            isSelected: snapshot.isSelected,
            isEnabled: snapshot.isEnabled,
            children: snapshot.children.map(node(from:))
        )
    }

    /// The element type as XCUITest names it in its own debug output, so a tree reads the way the app does under Accessibility Inspector.
    ///
    /// Spelled out rather than taken from `String(describing:)`, which prints raw enum case names that differ from the vocabulary anyone debugging a screen is looking at.
    ///
    /// **Every type the SDK defines is named**, because the core decides by name: `ScreenIdentifier` reads an identifier only on a container type it names, so a control written as a bare number — a segmented control as `Type37`, a menu item as `Type54` — could be told from a container only by the core knowing every number. Only a type a later SDK adds falls back to its numeric code, which the core then treats as no container at all — an honest number rather than an invented name. Bundles written before every type was named hold the popover, keyboard and search field as `Type18`, `Type19` and `Type45`, which the core still reads as those types.
    static func name(of type: XCUIElement.ElementType) -> String {
        names[type] ?? "Type\(type.rawValue)"
    }

    /// Each `XCUIElement.ElementType` by the name XCUITest's debug output gives it.
    private static let names: [XCUIElement.ElementType: String] = [
        .any: "Any", .other: "Other", .application: "Application", .group: "Group", .window: "Window", .sheet: "Sheet",
        .drawer: "Drawer", .alert: "Alert", .dialog: "Dialog", .button: "Button", .radioButton: "RadioButton",
        .radioGroup: "RadioGroup", .checkBox: "CheckBox", .disclosureTriangle: "DisclosureTriangle", .popUpButton: "PopUpButton",
        .comboBox: "ComboBox", .menuButton: "MenuButton", .toolbarButton: "ToolbarButton", .popover: "Popover",
        .keyboard: "Keyboard", .key: "Key", .navigationBar: "NavigationBar", .tabBar: "TabBar", .tabGroup: "TabGroup",
        .toolbar: "Toolbar", .statusBar: "StatusBar", .table: "Table", .tableRow: "TableRow", .tableColumn: "TableColumn",
        .outline: "Outline", .outlineRow: "OutlineRow", .browser: "Browser", .collectionView: "CollectionView",
        .slider: "Slider", .pageIndicator: "PageIndicator", .progressIndicator: "ProgressIndicator",
        .activityIndicator: "ActivityIndicator", .segmentedControl: "SegmentedControl", .picker: "Picker",
        .pickerWheel: "PickerWheel", .switch: "Switch", .toggle: "Toggle", .link: "Link", .image: "Image", .icon: "Icon",
        .searchField: "SearchField", .scrollView: "ScrollView", .scrollBar: "ScrollBar", .staticText: "StaticText",
        .textField: "TextField", .secureTextField: "SecureTextField", .datePicker: "DatePicker", .textView: "TextView",
        .menu: "Menu", .menuItem: "MenuItem", .menuBar: "MenuBar", .menuBarItem: "MenuBarItem", .map: "Map",
        .webView: "WebView", .incrementArrow: "IncrementArrow", .decrementArrow: "DecrementArrow", .timeline: "Timeline",
        .ratingIndicator: "RatingIndicator", .valueIndicator: "ValueIndicator", .splitGroup: "SplitGroup",
        .splitter: "Splitter", .relevanceIndicator: "RelevanceIndicator", .colorWell: "ColorWell", .helpTag: "HelpTag",
        .matte: "Matte", .dockItem: "DockItem", .ruler: "Ruler", .rulerMarker: "RulerMarker", .grid: "Grid",
        .levelIndicator: "LevelIndicator", .cell: "Cell", .layoutArea: "LayoutArea", .layoutItem: "LayoutItem",
        .handle: "Handle", .stepper: "Stepper", .tab: "Tab", .touchBar: "TouchBar", .statusItem: "StatusItem",
    ]
}
