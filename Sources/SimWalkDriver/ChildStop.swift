//
// Copyright © Agulhas Labs
//

import Foundation

/// Stops every child a shell made with ``Shell/stopped(by:)`` still has running, and every child it would run from then on — how one failing shard of a parallel walk ends the other shards' `xcodebuild` runs rather than waiting them out.
///
/// **Registration and the stop share one lock, so no child is left running.** A child is registered right after its launch, under the lock, and the registration is refused once the stop has happened; the stop marks itself stopped and takes the children registered so far in the same locked step. So a child launched alongside a stop is either registered first, and in the set the stop sweeps, or is refused, and its own `run` stops it. Each child is stopped with ``Shell``'s own escalation — `SIGTERM` to the child's pid (`Process.terminate()`), then, two seconds on, `SIGKILL` to the group it leads if any of that group stays, and to the pid if the child has still not exited — outside the lock, so a launch is never held up behind a stop's seconds of waiting.
public final class ChildStop: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [Int: Child] = [:]
    private var nextTicket = 0
    private var hasStopped = false
    /// Entered by the call that sweeps, under the lock in the step that marks the stop, and left once every child it found is stopped: what a later call waits on.
    private let sweep = DispatchGroup()

    public init() {}

    /// Whether ``stop()`` has been called — once true, it stays true.
    public var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasStopped
    }

    /// Stops every registered child and refuses every later one; a second call stops nothing itself, and waits for the first call's sweep.
    ///
    /// Returns once each child the first call found has been stopped — its group signalled and the child reaped, or the escalation's last wait spent — whichever call it is. **A later call waits rather than returning at once**: a Ctrl-C landing while a shard's failure is still escalating (`SIGTERM`, two seconds, `SIGKILL`) would otherwise give the devices back and end the process before the `SIGKILL`.
    public func stop() {
        lock.lock()
        guard !hasStopped else {
            lock.unlock()
            sweep.wait()
            return
        }
        hasStopped = true
        sweep.enter()
        let running = Array(children.values)
        lock.unlock()
        defer { sweep.leave() }
        // At once rather than one after another: each can spend seconds on its escalation, and the slowest should set the cost, not their sum.
        DispatchQueue.concurrentPerform(iterations: running.count) { index in
            let child = running[index]
            Shell.stop(child.process, group: child.group, exited: child.exited)
        }
    }

    /// Records a launched child, answering the ticket that deregisters it — or nil, registering nothing, when the stop has already happened and the caller has to stop the child itself.
    func register(_ child: Child) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !hasStopped else {
            return nil
        }
        nextTicket += 1
        children[nextTicket] = child
        return nextTicket
    }

    /// Forgets the child `ticket` names, once it has exited.
    func deregister(_ ticket: Int) {
        lock.lock()
        defer { lock.unlock() }
        children[ticket] = nil
    }
}

extension ChildStop {
    /// A running child as the stop needs it: the process, the group it leads (read at launch), and a semaphore its exit signals.
    ///
    /// **The semaphore is the stop's own, not the one its `run` waits on.** Both wait for the same exit, and a signal one waiter takes the other never sees: a `run` that took it would leave the stop waiting out its two seconds and then sending `SIGKILL` to a pid already reaped, which may by then be someone else's.
    struct Child {
        let process: Process
        let group: pid_t?
        let exited: DispatchSemaphore
    }
}
