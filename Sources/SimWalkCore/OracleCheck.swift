//
// Copyright © Agulhas Labs
//

import Foundation

/// Checks every figure a walkbook names against a value oracle, in every state a bundle captured (Brief §2.3).
///
/// Per figure per captured state: the figure is read from the capture's tree (`FigureScraper`) under the state's locale — else the device's — and one `OracleRequest` is asked for each figure that was read. A figure not on screen or not readable is answered as that and never asked about. All requests go to the oracle together, so a command oracle is one process per check rather than one per figure.
///
/// **A bundle without capture times is refused whole** (`OracleCheckError.noCaptureTime`) rather than checked with a guessed moment: a rolling window is computed back from the capture, and a figure matched under a guessed one is a match against nothing.
public struct OracleCheck {
    /// Every figure `walkbook` names, checked in every state `bundle` captured it in, in manifest order.
    ///
    /// The walkbook is matched to the bundle by screen id; that it is the walkbook the bundle was walked from (its `walkbookHash`) is the caller's to establish.
    public static func checks(of bundle: CaptureBundle, against walkbook: Walkbook, oracle: some ValueOracle) throws -> [FigureCheck] {
        let figuresByScreen = Dictionary(walkbook.screens.map { ($0.id, $0.figures ?? []) }) { first, _ in first }
        var slots: [Slot] = []
        for screen in bundle.manifest.screens {
            let figures = figuresByScreen[screen.id] ?? []
            guard !figures.isEmpty else { continue }
            for capture in screen.captures {
                guard let capturedAt = capture.capturedAt else {
                    throw OracleCheckError.noCaptureTime(screenID: screen.id, stateSlug: capture.state.slug)
                }
                let tree = try bundle.axTree(for: capture)
                let localeID = capture.state.locale ?? bundle.manifest.device.locale
                for figure in figures {
                    let slot = Slot(screenID: screen.id, stateSlug: capture.state.slug, figure: figure)
                    guard let localeID else {
                        slots.append(slot.settled(.unreadable(reason: "no locale is recorded for this state, so its separators cannot be read")))
                        continue
                    }
                    switch FigureScraper.reading(of: figure, in: tree, locale: Locale(identifier: localeID)) {
                    case let .read(onScreen):
                        let request = OracleRequest(figure: figure.id, windows: figure.windows, capturedAt: capturedAt, locale: localeID, screen: screen.id, state: capture.state.slug)
                        slots.append(slot.asking(request, about: onScreen))
                    case .notOnScreen:
                        slots.append(slot.settled(.notOnScreen(element: figure.element)))
                    case let .unreadable(reason):
                        slots.append(slot.settled(.unreadable(reason: reason)))
                    }
                }
            }
        }
        let requests = slots.compactMap(\.request)
        var answers = requests.isEmpty ? [] : oracle.answers(to: requests)
        if answers.count != requests.count {
            answers = requests.map { _ in .failed(reason: "it gave \(answers.count) answers to \(requests.count) requests") }
        }
        var next = answers.makeIterator()
        return slots.map { slot in
            let outcome = slot.outcome ?? slot.onScreen.flatMap { onScreen in
                next.next().map { FigureCheck.Outcome.matching(onScreen, windows: slot.figure.windows, answer: $0) }
            } ?? .oracleFailed(reason: "no answer")
            return FigureCheck(screenID: slot.screenID, stateSlug: slot.stateSlug, figureID: slot.figure.id, outcome: outcome)
        }
    }
}

extension OracleCheck {
    /// One figure in one state: settled without the oracle, or waiting on its answer to a request.
    struct Slot {
        let screenID: String
        let stateSlug: String
        let figure: Walkbook.Figure
        var outcome: FigureCheck.Outcome?
        var request: OracleRequest?
        var onScreen: OnScreenFigure?

        init(screenID: String, stateSlug: String, figure: Walkbook.Figure) {
            self.screenID = screenID
            self.stateSlug = stateSlug
            self.figure = figure
        }

        func settled(_ outcome: FigureCheck.Outcome) -> Slot {
            var slot = self
            slot.outcome = outcome
            return slot
        }

        func asking(_ request: OracleRequest, about onScreen: OnScreenFigure) -> Slot {
            var slot = self
            slot.request = request
            slot.onScreen = onScreen
            return slot
        }
    }
}
