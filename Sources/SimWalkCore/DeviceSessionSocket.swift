//
// Copyright © Agulhas Labs
//

import Foundation

/// The POSIX socket calls both ends of a device session make, written once so the two cannot differ in the options that keep a process alive.
///
/// **Every socket is non-blocking and waits in `poll(2)` against a deadline**, so no read, write or connect can outlast the timeout its caller chose; and **every socket carries `SO_NOSIGPIPE`**: a write to a peer that had gone raised SIGPIPE and ended the runner's test, `Test crashed with signal pipe.` (Brief, "Live sessions on a physical device", measured). With the option set the write fails with `EPIPE`, which each caller decides about.
struct DeviceSessionSocket {
    /// How many connections may wait behind the one being served; a host past it is refused and tries again.
    static var backlog: Int32 {
        4
    }

    /// Makes `descriptor` safe to use — no SIGPIPE on a write to a peer that has gone, and non-blocking — answering whether both took.
    static func prepare(_ descriptor: Int32) -> Bool {
        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    /// A listener bound to `address` — that address only, never the wildcard — on `port`.
    ///
    /// **Bound to the tunnel address, the kernel refuses the LAN before anything is accepted**; bound to `[::]`, the runner was reached from the Mac through the device's Wi-Fi IPv4 and IPv6 as well as the tunnel (Brief, "Live sessions on a physical device", measured).
    static func listen(address: String, port: UInt16) throws -> Int32 {
        var socketAddress = sockaddr_in6()
        socketAddress.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        socketAddress.sin6_family = sa_family_t(AF_INET6)
        socketAddress.sin6_port = port.bigEndian
        guard inet_pton(AF_INET6, address, &socketAddress.sin6_addr) == 1 else {
            throw DeviceSessionError.badAddress(address)
        }
        let descriptor = try opened(family: AF_INET6)
        let bound = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw DeviceSessionError.bindFailed(address: address, port: port, errno: code)
        }
        guard Darwin.listen(descriptor, backlog) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw DeviceSessionError.socketFailed(call: "listen", errno: code)
        }
        return descriptor
    }

    /// The next connection waiting on `listener`, prepared; `nil` when none is, or the one that was could not be taken — a host that gave up before it was accepted is not waiting for an answer.
    static func accept(_ listener: Int32) -> Int32? {
        let descriptor = Darwin.accept(listener, nil, nil)
        guard descriptor >= 0 else { return nil }
        guard prepare(descriptor) else {
            Darwin.close(descriptor)
            return nil
        }
        return descriptor
    }

    /// A connection to `address` and `port`, prepared, or the refusal the connect met within `timeout`.
    static func connect(address: String, port: UInt16, timeout: TimeInterval) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, String(port), &hints, &found) == 0, let info = found else {
            throw DeviceSessionClientError.badAddress(address)
        }
        defer { freeaddrinfo(found) }
        let descriptor: Int32
        do {
            descriptor = try opened(family: info.pointee.ai_family)
        } catch let DeviceSessionError.socketFailed(_, code) {
            throw DeviceSessionClientError.connectFailed(errno: code)
        }
        let deadline = ContinuousClock.now + .seconds(timeout)
        var outcome: Int32 = Darwin.connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 ? 0 : errno
        if outcome == EINPROGRESS {
            guard wait(descriptor, for: Int16(POLLOUT), until: deadline) else {
                Darwin.close(descriptor)
                throw DeviceSessionClientError.connectTimedOut(waited: timeout)
            }
            var pending: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            outcome = getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &pending, &length) == 0 ? pending : errno
        }
        guard outcome == 0 else {
            Darwin.close(descriptor)
            throw outcome == ECONNREFUSED ? DeviceSessionClientError.refused : DeviceSessionClientError.connectFailed(errno: outcome)
        }
        return descriptor
    }

    /// Reads one line of at most `cap` bytes from `descriptor` within `timeout`; bytes after the newline are left unread.
    static func readLine(_ descriptor: Int32, cap: Int, timeout: TimeInterval) -> LineRead {
        let deadline = ContinuousClock.now + .seconds(timeout)
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            guard wait(descriptor, for: Int16(POLLIN), until: deadline) else { return .timedOut }
            let count = recv(descriptor, &chunk, chunk.count, 0)
            if count == 0 {
                return .closed(received)
            }
            if count < 0 {
                let code = errno
                if code == EAGAIN || code == EINTR {
                    continue
                }
                return .failed(code)
            }
            let start = received.count
            received.append(contentsOf: chunk[0 ..< count])
            if let newline = received[start...].firstIndex(of: UInt8(ascii: "\n")) {
                return newline - received.startIndex > cap ? .overCap : .line(Data(received[..<newline]))
            }
            if received.count > cap {
                return .overCap
            }
        }
    }

    /// Writes all of `data` to `descriptor` within `timeout`, giving up with `ETIMEDOUT` once it passes however much has gone; answers the errno that stopped it, or `nil` when all of it went.
    ///
    /// **One deadline for the whole write**, never restarted by a partial one: a peer that reads a few bytes at a time would otherwise hold the writer for as long as it kept reading.
    static func send(_ descriptor: Int32, _ data: Data, timeout: TimeInterval) -> Int32? {
        var offset = 0
        let deadline = ContinuousClock.now + .seconds(timeout)
        while offset < data.count {
            guard wait(descriptor, for: Int16(POLLOUT), until: deadline) else { return ETIMEDOUT }
            let sent = data.withUnsafeBytes { buffer in
                Darwin.send(descriptor, buffer.baseAddress.map { $0 + offset }, data.count - offset, 0)
            }
            if sent < 0 {
                let code = errno
                if code == EAGAIN || code == EINTR {
                    continue
                }
                return code
            }
            offset += sent
        }
        return nil
    }

    /// Waits until `descriptor` is ready for `events`, or has an error or hang-up the next call will report; `false` once `deadline` passes first.
    static func wait(_ descriptor: Int32, for events: Int16, until deadline: ContinuousClock.Instant) -> Bool {
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            let milliseconds = max(0, remaining.components.seconds * 1000 + remaining.components.attoseconds / 1_000_000_000_000_000)
            var request = pollfd(fd: descriptor, events: events, revents: 0)
            let ready = poll(&request, 1, Int32(clamping: milliseconds))
            if ready > 0 {
                return true
            }
            if ready < 0, errno != EINTR {
                return true
            }
            if ready == 0, milliseconds == 0 {
                return false
            }
        }
    }

    /// A new TCP socket of `family`, prepared.
    private static func opened(family: Int32) throws -> Int32 {
        let descriptor = Darwin.socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard descriptor >= 0 else {
            throw DeviceSessionError.socketFailed(call: "socket", errno: errno)
        }
        guard prepare(descriptor) else {
            let code = errno
            Darwin.close(descriptor)
            throw DeviceSessionError.socketFailed(call: "setsockopt", errno: code)
        }
        return descriptor
    }
}

extension DeviceSessionSocket {
    /// What reading one frame came to.
    enum LineRead: Equatable {
        /// A whole line, its newline stripped.
        case line(Data)
        /// The peer closed before a newline, having sent these bytes.
        case closed(Data)
        /// No newline within the wait.
        case timedOut
        /// More than the cap arrived without a newline.
        case overCap
        /// The read failed with this errno — a reset peer, say.
        case failed(Int32)
    }
}
