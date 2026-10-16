//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The pseudonyms a shared `simwalk usage` report carries in place of failure reasons.
struct RedactorTests {
    /// One reason, one token, under one salt — which is what lets grouping survive redaction and a reason still costing walks next week read as the same row.
    @Test
    func thesameReasonUnderTheSameSaltIsTheSameToken() {
        let redactor = Redactor(salt: Data("salt".utf8))

        #expect(redactor.reason("the walk did not complete: crash") == Redactor(salt: Data("salt".utf8)).reason("the walk did not complete: crash"))
        #expect(redactor.reason("the walk did not complete: crash") != redactor.reason("the walk did not complete: snapshot"))
        #expect(redactor.reason("x").wholeMatch(of: /reason-[0-9a-f]{6}/) != nil)
    }

    /// A different machine's salt gives different tokens, so nobody off the machine can test a guessed sentence against one.
    @Test
    func adifferentSaltGivesADifferentToken() {
        #expect(Redactor(salt: Data("a".utf8)).reason("x") != Redactor(salt: Data("b".utf8)).reason("x"))
    }

    /// The machine's salt is made once and reused, so tokens agree from one report to the next.
    @Test
    func thestandardSaltIsCreatedOnceAndReused() throws {
        let directory = try TemporaryDirectory()
        let saltFile = directory.url.appendingPathComponent("nested").appendingPathComponent("redaction-salt")

        let first = Redactor.standard(saltFile: saltFile).reason("x")
        let second = Redactor.standard(saltFile: saltFile).reason("x")

        #expect(FileManager.default.fileExists(atPath: saltFile.path))
        #expect(first == second)
    }

    /// The salt file is private to its owner.
    ///
    /// A shared host under `SIMWALK_USAGE_LOG` puts the salt somewhere other local users can read; 0644 would let them, and a token they cannot invert this cheaply is a redaction, not a plaintext salt they can read directly off disk.
    @Test
    func thesaltFileIsCreatedPrivateToItsOwner() throws {
        let directory = try TemporaryDirectory()
        let saltFile = directory.url.appendingPathComponent("redaction-salt")

        _ = Redactor.standard(saltFile: saltFile)
        let attributes = try FileManager.default.attributesOfItem(atPath: saltFile.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(permissions.uint16Value & 0o777 == 0o600)
    }

    /// Concurrent first use must not be last-writer-wins.
    ///
    /// Every racer has to end up keying its tokens off the same bytes as whichever one the filesystem actually kept, or a report holds tokens under a salt nobody else's report — including the file left on disk — shares. Measured without the fix: one of six parallel first runs printed tokens under a salt a plain `.atomic` write then let a second creator overwrite.
    @Test
    func concurrentFirstUseAgreesOnOneSalt() throws {
        let directory = try TemporaryDirectory()
        let saltFile = directory.url.appendingPathComponent("redaction-salt")
        let collector = TokenCollector()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            collector.append(Redactor.standard(saltFile: saltFile).reason("x"))
        }

        #expect(Set(collector.all).count == 1)
    }
}

extension RedactorTests {
    /// A racing token, collected off whichever thread `DispatchQueue.concurrentPerform` ran it on.
    private final class TokenCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [String] = []

        func append(_ token: String) {
            lock.withLock { tokens.append(token) }
        }

        var all: [String] {
            lock.withLock { tokens }
        }
    }
}
