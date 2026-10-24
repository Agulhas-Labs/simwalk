//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver

/// The walks of one run whose device handback is still to come, which an interruption waits for, bounded, before it gives the devices back (SimWalk#187).
///
/// A SIGINT or SIGTERM ends the process as soon as its cancel handlers return, and the walk puts a device's appearance, accessibility and setup back only after its runner. A walk enters before it touches its device and leaves once it has handed it back; the interruption closes the gate, so no walk starts on a device about to be given back, and waits for the walks inside before the leases go.
///
/// Unchecked because the walks inside and the closed flag are only touched under `condition`.
final class HandbackGate: @unchecked Sendable {
    /// How long an interruption waits for the handbacks under way: the accessibility restore alone may wait about ten seconds for the runner's teardown and ten more to confirm, and the appearance and the setup come after it.
    static let interruptionBound: TimeInterval = 30

    private let condition = NSCondition()
    /// The device each walk inside hands back, by its ticket.
    private var inside: [Int: String] = [:]
    private var nextTicket = 0
    private var closed = false

    /// Counts in the walk that hands `udid` back, or refuses it with the walk's own stop (``ShellError/stopped``) once the interruption has closed the gate.
    func enter(_ udid: String) throws -> Entry {
        try condition.withLock {
            guard !closed else { throw ShellError.stopped }
            let ticket = nextTicket
            nextTicket += 1
            inside[ticket] = udid
            return Entry(gate: self, ticket: ticket)
        }
    }

    /// Closes the gate, so every later ``enter(_:)`` is refused, and answers the devices whose handback is still to come.
    func close() -> [String] {
        condition.withLock {
            closed = true
            return devicesInside
        }
    }

    /// Waits until every walk inside has left, or `bound` seconds have passed, and answers the devices still inside then.
    func wait(upTo bound: TimeInterval) -> [String] {
        let deadline = Date().addingTimeInterval(bound)
        return condition.withLock {
            while !inside.isEmpty, condition.wait(until: deadline) {}
            return devicesInside
        }
    }

    private func leave(_ ticket: Int) {
        condition.withLock {
            guard inside.removeValue(forKey: ticket) != nil else { return }
            condition.broadcast()
        }
    }

    /// In the order the walks entered, read under `condition`.
    private var devicesInside: [String] {
        inside.sorted { $0.key < $1.key }.map(\.value)
    }
}

extension HandbackGate {
    /// One walk's place inside the gate, given up by ``leave()``.
    struct Entry: Sendable {
        fileprivate let gate: HandbackGate
        fileprivate let ticket: Int

        /// Leaves the gate; a second call does nothing, so a `defer` and the call after the handback can both run it.
        func leave() {
            gate.leave(ticket)
        }
    }
}
