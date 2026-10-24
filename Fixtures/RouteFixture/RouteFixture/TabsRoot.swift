//
// Copyright © Agulhas Labs
//

import SwiftUI

/// The tabs mode (`-RouteFixtureTabs`): a sidebar-adaptable `TabView` with one tab per walk-behaviour shape `tabs.walkbook.json` walks — the floating bottom bar on iPhone, the floating top bar on iPad. Launches on Hub.
struct TabsRoot: View {
    var body: some View {
        TabView {
            Tab("Hub", systemImage: "house") { HubScreen() }
            Tab("Rows", systemImage: "list.bullet") { RowsScreen() }
            Tab("Menus", systemImage: "filemenu.and.selection") { MenusScreen() }
            Tab("Nested", systemImage: "square.stack") { NestedScreen() }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Twenty plain rows and then `Open form`, below the fold on iPhone — SimWalk#104 (a tap right after a push) and SimWalk#106 (a launch-argument deep link, `-RouteFixturePushForm`, that pushes the form on first appearance). Above them two rows for the gestures: `Press row`, whose context menu holds `Open details` (the `longPress` step), and `Swipe row`, whose trailing swipe action `Archive` is revealed by a swipe left (the `swipe` step) — SimWalk#198.
private struct HubScreen: View {
    @State private var path: [HubRoute] = []
    @State private var pushedOnLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink("Danger zone") { DangerScreen() }
                Button("Press row") {}
                    .contextMenu {
                        Button("Open details") { path.append(.menuDetail) }
                    }
                Button("Swipe row") {}
                    .swipeActions(edge: .trailing) {
                        Button("Archive") { path.append(.swipeDetail) }
                    }
                ForEach(1 ... 20, id: \.self) { Text("Hub row \($0)") }
                NavigationLink("Open form", value: HubRoute.form)
                NavigationLink("Open replace specimens", value: HubRoute.replaceSpecimens)
                NavigationLink("Open drag specimens", value: HubRoute.dragSpecimens)
            }
            .accessibilityIdentifier("hub-screen")
            .navigationTitle("Hub")
            .navigationDestination(for: HubRoute.self) { route in
                switch route {
                case .form: FormScreen()
                case .replaceSpecimens: ReplaceSpecimensScreen()
                case .dragSpecimens: DragSpecimensScreen()
                case .menuDetail: GestureDestination(title: "Menu details", identifier: "menu-detail-screen")
                case .swipeDetail: GestureDestination(title: "Archived", identifier: "swipe-detail-screen")
                }
            }
        }
        .onAppear {
            guard !pushedOnLaunch, ProcessInfo.processInfo.arguments.contains("-RouteFixturePushForm") else { return }
            pushedOnLaunch = true
            path = [.form]
        }
    }
}

private enum HubRoute: Hashable {
    case form
    case replaceSpecimens
    case dragSpecimens
    case menuDetail
    case swipeDetail
}

/// What a context-menu item or a swipe action pushes: a screen with an identifier of its own, so a walk can tell which gesture reached it (SimWalk#198).
private struct GestureDestination: View {
    let title: String
    let identifier: String

    var body: some View {
        List { Text(title) }
            .accessibilityIdentifier(identifier)
            .navigationTitle(title)
    }
}

/// A `Volume` slider (0 to 100, starting at 0) for the `drag` step (`drag-specimens.walkbook.json`, SimWalk#148). The text below it carries the slider's value in its identifier (`volume-<n>` for n up to 80, then the coarse bucket `volume-high` above it, so a drag across lands on one stable identifier whatever the exact value). The screen's own identifier follows the same bucket (`drag-specimens-screen`, then `drag-specimens-high`), because `expect` reads screen-level identifiers and never an element's own: the walkbook `expect`s `drag-specimens-high`, so a drag that did nothing fails the walk, and it is also a form difference in `bundle diff`, which compares identifiers and never values.
private struct DragSpecimensScreen: View {
    @State private var volume = 0.0

    var body: some View {
        Form {
            Section {
                Slider(value: $volume, in: 0 ... 100).accessibilityLabel("Volume")
                Text("Volume is \(Int(volume))").accessibilityIdentifier(volume > 80 ? "volume-high" : "volume-\(Int(volume))")
            }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("Drag specimens")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(volume > 80 ? "drag-specimens-high" : "drag-specimens-screen")
    }
}

/// Five fields the `type` step's `replace: true` should refuse or struggle with, one walkbook screen each (`replace-specimens.walkbook.json`, SimWalk#214): `Long` holds a left-to-right sentence far wider than the field, `Shout` uppercases what is typed so the read-back differs from the text, `Later` uppercases the field 0.4 s after the edit (SimWalk#219), `Secret` is a secure field, and `Locked` is disabled so a tap leaves it without keyboard focus. Each is followed by text carrying its value (`long-<length>` for `Long`) so a changed value is a form difference in `bundle diff`. They sit in the first section so none is under the keyboard.
private struct ReplaceSpecimensScreen: View {
    @State private var long = "The quick brown fox jumps over the lazy dog and keeps on running past the edge of this field until it is long"
    @State private var shout = "quiet"
    @State private var later = "quiet"
    @State private var secret = "hunter2"
    @State private var locked = "fixed"

    var body: some View {
        Form {
            Section {
                TextField("Long", text: $long).accessibilityLabel("Long").autocorrectionDisabled()
                Text("Long is \(long.count) characters").accessibilityIdentifier("long-\(long.count)")
                ShoutingField(text: $shout).frame(height: 22)
                Text("Shout is \(shout)").accessibilityIdentifier("shout-\(shout)")
                LaterField(text: $later).frame(height: 22)
                Text("Later is \(later)").accessibilityIdentifier("later-\(later)")
                SecureField("Secret", text: $secret).accessibilityLabel("Secret").autocorrectionDisabled()
                Text("Secret has \(secret.count) characters").accessibilityIdentifier("secret-\(secret.count)")
                TextField("Locked", text: $locked).accessibilityLabel("Locked").autocorrectionDisabled().disabled(true)
                Text("Locked is \(locked)").accessibilityIdentifier("locked-\(locked)")
            }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("Replace specimens")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("replace-specimens-screen")
    }
}

/// `Later`: a UIKit field whose delegate accepts every edit as typed and uppercases the field 0.4 s afterwards, as a formatter on a later run loop would, so a read straight after typing sees the text and a settled read sees its uppercase (SimWalk#219). **A demonstration, not a pin**: whether a single read lands it depends on how long XCUITest takes between the last keystroke and the read, which load moves either way; the settle's decision is pinned by `FieldValueSettle`'s unit tests.
private struct LaterField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.placeholder = "Later"
        field.accessibilityLabel = "Later"
        field.autocorrectionType = .no
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ field: UITextField, context _: Context) {
        if field.text != text {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let changed = ((field.text ?? "") as NSString).replacingCharacters(in: range, with: string)
            text.wrappedValue = changed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [text] in
                let uppercased = (field.text ?? "").uppercased()
                field.text = uppercased
                text.wrappedValue = uppercased
                // Setting the text moves the cursor to the end, where it should stay.
                field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
            }
            return true
        }
    }
}

/// `Shout`: a UIKit field whose delegate inserts every edit uppercased, synchronously, so what is typed always reads back as its uppercase (SimWalk#214). A SwiftUI `onChange` rewrite lost the last typed character in some walks (`LOUd`), and a rewrite in the binding's setter changed the state without the field showing it.
private struct ShoutingField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.placeholder = "Shout"
        field.accessibilityLabel = "Shout"
        field.autocorrectionType = .no
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ field: UITextField, context _: Context) {
        if field.text != text {
            field.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = (field.text ?? "") as NSString
            let changed = current.replacingCharacters(in: range, with: string.uppercased())
            field.text = changed
            text.wrappedValue = changed
            // Setting the text moves the cursor to the end; put it back after the edit, as the field would have.
            if let position = field.position(from: field.beginningOfDocument, offset: range.location + (string as NSString).length) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            return false
        }
    }
}

/// The form Hub pushes, in the shape of the real app's: a pushed `Form` with an inline title and an `Add entry` button that opens a sheet identified `form-sheet` — SimWalk#104, #106.
///
/// It also holds a `Nickname` field pre-filled with `Draft`, for the `type` step's `replace` (SimWalk#198). The text below it carries the field's current value in its identifier (`nickname-Draft`, then `nickname-Robin`), so a replace that stopped landing is a form difference in `bundle diff`, which compares identifiers and never values. The fields turn autocorrection off, which hides the keyboard's suggestion bar: its words change from walk to walk and showed as overlaps in `bundle diff` between two walks of one build (SimWalk#215). `Amount` is trailing-aligned and `Notes` is multi-line, the two shapes where a tap at a field's centre leaves the cursor mid-text (SimWalk#198); they sit in the first section so neither is under the keyboard. `Nickname` carries no label on purpose: a filled SwiftUI `TextField` exposes its title only as the placeholder, which a `type` step reaches when nothing carries the label (SimWalk#212).
private struct FormScreen: View {
    @State private var showsSheet = false
    @State private var nickname = "Draft"
    @State private var amount = "1250"
    @State private var notes = "First line\nSecond line"

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: $amount).multilineTextAlignment(.trailing).accessibilityLabel("Amount").autocorrectionDisabled()
                Text("Amount is \(amount)").accessibilityIdentifier("amount-\(amount)")
                TextField("Notes", text: $notes, axis: .vertical).accessibilityLabel("Notes").autocorrectionDisabled()
                Text("Notes are \(notes)").accessibilityIdentifier("notes-\(notes)")
            }
            Section { ForEach(1 ... 3, id: \.self) { Text("Entry \($0)") } }
            Section { Button("Add entry") { showsSheet = true }.accessibilityIdentifier("form-add") }
            Section {
                TextField("Nickname", text: $nickname).autocorrectionDisabled()
                Text("Nickname is \(nickname)").accessibilityIdentifier("nickname-\(nickname)")
            }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("Form")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("form-screen")
        .sheet(isPresented: $showsSheet) {
            Text("Sheet")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("form-sheet")
        }
    }
}

/// A row that starts about 24 pt above the bottom of the safe area, so most of it sits under the floating tab bar at launch — SimWalk#108 (`scrollTo` must not settle the target still overlapping the tab bar).
private struct RowsScreen: View {
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(0, proxy.size.height - 24))
                        Text("Partly covered row")
                            .frame(maxWidth: .infinity, minHeight: 60)
                        ForEach(1 ... 30, id: \.self) { row in
                            Text("Filler row \(row)")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rows-screen")
            .navigationTitle("Rows")
        }
    }
}

/// A `Menu` whose open popover the tree does not carry under any identifier — SimWalk#111 (`expect` after a tap that opens a menu).
private struct MenusScreen: View {
    var body: some View {
        NavigationStack {
            VStack {
                Menu("Kind") {
                    Button("Endurance") {}
                    Button("Walking") {}
                    Button("Strength") {}
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("menus-screen")
            .navigationTitle("Menus")
        }
    }
}

/// An identified scroll view holding an identified container — SimWalk#103 (both identifiers must reach the tree on non-element nodes, outer first).
private struct NestedScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Outer heading")
                    VStack(alignment: .leading) {
                        Text("Inner body")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nested-inner")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .accessibilityIdentifier("nested-outer")
            .navigationTitle("Nested")
        }
    }
}

/// A destructive button and the state it sets, for `simwalk discover` to leave alone: `Erased: no` after a crawl means the crawl never tapped `Erase All`. Launching with `-RouteFixtureResetErased` clears the flag.
private struct DangerScreen: View {
    @AppStorage("RouteFixtureErased") private var erased = false

    var body: some View {
        List {
            Button("Erase All", role: .destructive) { erased = true }
            Text(erased ? "Erased: yes" : "Erased: no")
        }
        .accessibilityIdentifier("danger-screen")
        .navigationTitle("Danger zone")
    }
}
