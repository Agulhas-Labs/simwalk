//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Reading a figure off a captured tree: by identifier, then label; under the capture's locale; and never a `0` for a figure that is not there.
struct FigureScraperTests {
    private static let steps = Walkbook.Figure(id: "steps-today", element: "steps-today", windows: ["midnight"])

    @Test
    func aGroupedFigureIsReadUnderItsLocale() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "2,703 steps"), locale: Locale(identifier: "en_US"))

        #expect(reading == .read(OnScreenFigure(printed: "2,703", value: 2703, fractionDigits: 0, unit: "steps")))
    }

    /// A decimal comma, in the locale that writes one: `4,2 km` is four point two, printed to one place.
    @Test
    func aDecimalCommaIsReadUnderALocaleThatWritesOne() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "4,2 km"), locale: Locale(identifier: "de_DE"))

        #expect(reading == .read(OnScreenFigure(printed: "4,2", value: 4.2, fractionDigits: 1, unit: "km")))
    }

    @Test
    func aSpaceGroupedFigureIsReadInFrench() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "12\u{202F}703,5"), locale: Locale(identifier: "fr_FR"))

        #expect(reading == .read(OnScreenFigure(printed: "12\u{202F}703,5", value: 12703.5, fractionDigits: 1, unit: nil)))
    }

    /// `3,43` is not a number `en_US` draws, so it is refused rather than read as three hundred and forty-three.
    @Test
    func groupsAFormatterWouldNotDrawAreRefused() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "3,43"), locale: Locale(identifier: "en_US"))

        #expect(reading == .unreadable(reason: "'3,43' is not a number as en_US writes one"))
    }

    @Test
    func aFigureNothingCarriesIsNotOnScreenRatherThanZero() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "2,703", identifier: nil), locale: Locale(identifier: "en_US"))

        #expect(reading == .notOnScreen)
    }

    @Test
    func anElementWithNoNumberIsUnreadableRatherThanZero() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "—"), locale: Locale(identifier: "en_US"))

        #expect(reading == .unreadable(reason: "'—' carries no number"))
    }

    /// With no identifier on screen, the element is read as a label pattern whose `{n}` is the figure.
    @Test
    func aLabelPatternReadsTheNumberItsPlaceholderStandsFor() {
        let figure = Walkbook.Figure(id: "steps-today", element: "Steps today {n}", windows: ["midnight"])
        let reading = FigureScraper.reading(of: figure, in: FigureFixture.screen(text: "Steps today 2,703", identifier: nil), locale: Locale(identifier: "en_US"))

        #expect(reading == .read(OnScreenFigure(printed: "2,703", value: 2703, fractionDigits: 0, unit: nil)))
    }

    /// The element is on screen showing a placeholder: that is no figure, not an element that is missing.
    @Test
    func aLabelPatternOverAPlaceholderIsUnreadableNotAbsent() {
        let figure = Walkbook.Figure(id: "steps-today", element: "Steps: {n}", windows: ["midnight"])
        let reading = FigureScraper.reading(of: figure, in: FigureFixture.screen(text: "Steps: —", identifier: nil), locale: Locale(identifier: "en_US"))

        #expect(reading == .unreadable(reason: "'Steps: —' carries no number"))
    }

    /// A heading that shares one of the pattern's literals is not the figure's element showing a placeholder.
    @Test
    func aLabelPatternOverTextWithLettersIsStillNotOnScreen() {
        let figure = Walkbook.Figure(id: "steps-today", element: "{n} steps", windows: ["midnight"])
        let reading = FigureScraper.reading(of: figure, in: FigureFixture.screen(text: "Daily steps", identifier: nil), locale: Locale(identifier: "en_US"))

        #expect(reading == .notOnScreen)
    }

    @Test
    func aLabelPatternWhoseLiteralsDoNotMatchIsStillNotOnScreen() {
        let figure = Walkbook.Figure(id: "steps-today", element: "Steps: {n}", windows: ["midnight"])
        let reading = FigureScraper.reading(of: figure, in: FigureFixture.screen(text: "Distance: —", identifier: nil), locale: Locale(identifier: "en_US"))

        #expect(reading == .notOnScreen)
    }

    @Test
    func twoDigitInnerGroupsAreRefusedWhereTheLocaleDoesNotGroupInTwos() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "1,23,456"), locale: Locale(identifier: "en_US"))

        #expect(reading == .unreadable(reason: "'1,23,456' is not a number as en_US writes one"))
    }

    @Test
    func aLakhGroupedFigureIsReadInIndianEnglish() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "1,23,456"), locale: Locale(identifier: "en_IN"))

        #expect(reading == .read(OnScreenFigure(printed: "1,23,456", value: 123_456, fractionDigits: 0, unit: nil)))
    }

    /// SimWalk#92: only the lakh pattern is a figure in en_IN, so a mixed inner grouping is refused.
    @Test(arguments: [("12,34,56,789", 123_456_789.0), ("1,23,456", 123_456.0)])
    func theLakhPatternIsReadInIndianEnglish(printed: String, value: Double) {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: printed), locale: Locale(identifier: "en_IN"))

        #expect(reading == .read(OnScreenFigure(printed: printed, value: value, fractionDigits: 0, unit: nil)))
    }

    @Test
    func aMixedInnerGroupingIsRefusedInIndianEnglish() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "1,234,56,789"), locale: Locale(identifier: "en_IN"))

        #expect(reading == .unreadable(reason: "'1,234,56,789' is not a number as en_IN writes one"))
    }

    @Test
    func threeDigitGroupsStillReadInEnglishUS() {
        let reading = FigureScraper.reading(of: Self.steps, in: FigureFixture.screen(text: "123,456"), locale: Locale(identifier: "en_US"))

        #expect(reading == .read(OnScreenFigure(printed: "123,456", value: 123_456, fractionDigits: 0, unit: nil)))
    }
}
