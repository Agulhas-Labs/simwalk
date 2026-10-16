//
// Copyright © Agulhas Labs
//

import Foundation

/// What one capture shows of one figure: a number read, nothing there to read, or something there that is not one number.
///
/// **Absent is never zero.** A figure the screen does not draw, and an element that carries no parsable number, are answers of their own — a `0` standing in for either would match an oracle's empty window and pass.
public enum FigureReading: Equatable, Sendable {
    /// The element was found and carried exactly one number.
    case read(OnScreenFigure)
    /// Nothing in the tree carries the figure's element as an identifier or a label.
    case notOnScreen
    /// Something carries the element, but no single number could be read from it; the reason names the text.
    case unreadable(reason: String)
}
