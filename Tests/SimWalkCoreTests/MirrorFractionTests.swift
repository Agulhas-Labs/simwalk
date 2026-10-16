//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A mirror coordinate is a fraction of the window, refused outside `0…1`, and mapped to a display point from the window's own origin and size.
struct MirrorFractionTests {
    private static let window = MirrorWindowFrame(windowID: 1018, x: 672, y: 118, width: 383, height: 843)

    /// The corners map to the window's corners and the centre to its middle, offset by the window's origin.
    @Test
    func cornersAndCentreMapIntoAnOffOriginWindow() throws {
        let window = Self.window

        #expect(try window.point(for: MirrorFraction(x: 0, y: 0)) == MirrorWindowFrame.Point(x: 672, y: 118))
        #expect(try window.point(for: MirrorFraction(x: 1, y: 0)) == MirrorWindowFrame.Point(x: 1054, y: 118))
        #expect(try window.point(for: MirrorFraction(x: 0, y: 1)) == MirrorWindowFrame.Point(x: 672, y: 960))
        #expect(try window.point(for: MirrorFraction(x: 1, y: 1)) == MirrorWindowFrame.Point(x: 1054, y: 960))
        #expect(try window.point(for: MirrorFraction(x: 0.5, y: 0.5)) == MirrorWindowFrame.Point(x: 863.5, y: 539.5))
    }

    /// Points on the phone's screen pass; the transparent border round it and the rounded corners are refused naming the fraction.
    @Test
    func theBorderAndTheCornersAreRefused() throws {
        let window = Self.window
        let corner = try MirrorFraction(x: 0.03, y: 0.06)
        let border = try MirrorFraction(x: 0.01, y: 0.5)
        let top = try MirrorFraction(x: 0.5, y: 0.03)

        #expect(try window.target(for: MirrorFraction(x: 0.5, y: 0.5)) == MirrorWindowFrame.Point(x: 863.5, y: 539.5))
        #expect(try window.target(for: MirrorFraction(x: 0.03, y: 0.5)) == window.point(for: MirrorFraction(x: 0.03, y: 0.5)))
        #expect(try window.target(for: MirrorFraction(x: 0.2, y: 0.06)) == window.point(for: MirrorFraction(x: 0.2, y: 0.06)))
        #expect(throws: MirrorWindowFrame.PassThrough(fraction: corner)) {
            try window.target(for: corner)
        }
        #expect(throws: MirrorWindowFrame.PassThrough(fraction: border)) {
            try window.target(for: border)
        }
        #expect(throws: MirrorWindowFrame.PassThrough(fraction: top)) {
            try window.target(for: top)
        }
        #expect(throws: MirrorWindowFrame.PassThrough.self) {
            try window.target(for: MirrorFraction(x: 1, y: 1))
        }
        #expect(MirrorWindowFrame.PassThrough(fraction: corner).localizedDescription.contains("x = 0.03, y = 0.06"))
    }

    /// A window at the display's origin maps a fraction to its size times the fraction.
    @Test
    func aWindowAtTheOriginMapsByItsSize() throws {
        let window = MirrorWindowFrame(windowID: 1, x: 0, y: 0, width: 400, height: 800)

        #expect(try window.point(for: MirrorFraction(x: 0.25, y: 0.75)) == MirrorWindowFrame.Point(x: 100, y: 600))
    }

    /// Just past either edge, and not a number, are refused naming the axis and the value.
    @Test
    func valuesOutsideTheWindowAreRefused() {
        #expect(throws: MirrorFraction.OutOfRange(axis: "x", value: -0.01)) {
            try MirrorFraction(x: -0.01, y: 0.5)
        }
        #expect(throws: MirrorFraction.OutOfRange(axis: "y", value: 1.01)) {
            try MirrorFraction(x: 0.5, y: 1.01)
        }
        #expect(throws: MirrorFraction.OutOfRange(axis: "x", value: .nan)) {
            try MirrorFraction(x: .nan, y: 0.5)
        }
        #expect(throws: MirrorFraction.OutOfRange(axis: "y", value: .infinity)) {
            try MirrorFraction(x: 0.5, y: .infinity)
        }
        #expect(MirrorFraction.OutOfRange(axis: "y", value: 1.01).localizedDescription.contains("y = 1.01"))
    }
}
