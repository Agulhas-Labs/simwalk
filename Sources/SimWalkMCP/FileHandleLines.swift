//
// Copyright © Agulhas Labs
//

import Foundation

/// Bridges a `FileHandle` to an async sequence of newline-delimited strings via GCD's readability handler.
///
/// Deliberately not `FileHandle.bytes.lines`: on pipes that path can stall off the main run loop, and a stalled read is a hung server. The readability handler is plain GCD and behaves the same way everywhere.
///
/// A value rather than a static function so the reader can be **ended from outside**. A server that has lost its output has nothing left to answer with, and waiting for the client to close its end of stdin first is waiting on the half of the connection that already failed — ``finish()`` is what lets the write path end the read loop.
struct FileHandleLines {
    /// The lines, until EOF or ``finish()``; a trailing unterminated line is delivered before finishing.
    let lines: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation

    /// `hearing` sees each line as it is read, before it is queued for the consumer — on the reader's own queue, so a consumer busy with a long request does not hold it up.
    init(reading handle: FileHandle, hearing: @escaping @Sendable (String) -> Void = { _ in }) {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        lines = stream
        self.continuation = continuation

        let accumulator = Accumulator()
        handle.readabilityHandler = { readHandle in
            let chunk = readHandle.availableData
            if chunk.isEmpty {
                if let remainder = accumulator.drainRemainder() {
                    hearing(remainder)
                    continuation.yield(remainder)
                }
                continuation.finish()
                readHandle.readabilityHandler = nil
                return
            }
            for line in accumulator.append(chunk) {
                hearing(line)
                continuation.yield(line)
            }
        }
        continuation.onTermination = { _ in
            handle.readabilityHandler = nil
        }
    }

    /// Ends the stream without waiting for EOF, so a consumer that can no longer answer stops reading.
    func finish() {
        continuation.finish()
    }
}

extension FileHandleLines {
    /// A byte buffer splitting on `0x0A`, confined to the readability handler's serial callbacks.
    ///
    /// A JSON-RPC request can arrive split across reads, or several can arrive in one — so the split has to be over an accumulated buffer rather than over each chunk, or a request would be parsed as two halves that are each not JSON.
    final class Accumulator: @unchecked Sendable {
        private var buffer = Data()

        /// Appends a chunk and returns every complete line it closed.
        func append(_ chunk: Data) -> [String] {
            buffer.append(chunk)
            var lines: [String] = []
            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex ..< newlineRange.lowerBound)
                buffer = buffer.subdata(in: newlineRange.upperBound ..< buffer.endIndex)
                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line)
                }
            }
            return lines
        }

        /// The trailing unterminated line at EOF, if any.
        func drainRemainder() -> String? {
            guard !buffer.isEmpty else { return nil }
            defer { buffer = Data() }
            return String(data: buffer, encoding: .utf8)
        }
    }
}
