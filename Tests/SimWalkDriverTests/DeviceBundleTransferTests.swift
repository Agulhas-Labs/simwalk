//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a bundle copied back from a device may look like at the output path: a complete one, or nothing.
struct DeviceBundleTransferTests {
    private func makeBundle(in directory: TemporaryDirectory) throws -> CaptureBundle {
        let capture = CaptureBundleFixture.Capture(
            screenID: "today",
            state: Walkbook.CaptureState(theme: .light, locale: "en_US"),
            tree: FigureFixture.screen(text: "2,703")
        )
        return try CaptureBundleFixture.write(in: directory, captures: [capture])
    }

    private func leftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".partial-") }
    }

    /// A copy cut off after any number of files leaves no bundle and no staging directory — the manifest-first order included, where the manifest arrives and the artefacts it names do not.
    @Test
    func anInterruptedCopyLeavesNothingAtTheOutputForEveryCutPoint() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let count = try FakeCopier.files(of: bundle.url).count
        #expect(count > 1)

        for cut in 0 ..< count {
            let host = try TemporaryDirectory()
            let output = host.url.appendingPathComponent("walk.simwalk")

            #expect(throws: DeviceTransferError.self) {
                try DeviceBundleTransfer.fetch(source: "Documents/SimWalkOut/walk.simwalk", to: output, copier: FakeCopier(bundle: bundle.url, limit: cut))
            }
            #expect(!FileManager.default.fileExists(atPath: output.path), "cut after \(cut) files left a bundle")
            #expect(try leftovers(in: host.url).isEmpty, "cut after \(cut) files left a staging directory")
        }
    }

    /// The copy goes to a staging sibling and nothing exists at the output until the rename: a "copy to output, delete on error" implementation fails the fake copier's own assertions.
    @Test
    func theCopyIsStagedAwayFromTheOutput() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let host = try TemporaryDirectory()
        let output = host.url.appendingPathComponent("walk.simwalk")

        _ = try DeviceBundleTransfer.fetch(source: "x", to: output, copier: FakeCopier(bundle: bundle.url, guarding: output))
    }

    /// A parent directory that does not exist yet is created, for a copier that makes no intermediates.
    @Test
    func aMissingOutputParentIsCreated() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let host = try TemporaryDirectory()
        let output = host.url.appendingPathComponent("a/b/walk.simwalk")

        let fetched = try DeviceBundleTransfer.fetch(source: "x", to: output, copier: FakeCopier(bundle: bundle.url, makesIntermediates: false))

        #expect(fetched.url == output)
    }

    /// An empty directory at the output is replaced; one that gained contents during the copy is refused and left alone.
    @Test
    func anEmptyDirectoryAtTheOutputIsReplacedButOneThatFilledIsNot() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)

        let empty = try TemporaryDirectory()
        let emptyOutput = empty.url.appendingPathComponent("walk.simwalk")
        try FileManager.default.createDirectory(at: emptyOutput, withIntermediateDirectories: false)
        _ = try DeviceBundleTransfer.fetch(source: "x", to: emptyOutput, copier: FakeCopier(bundle: bundle.url))

        let filled = try TemporaryDirectory()
        let filledOutput = filled.url.appendingPathComponent("walk.simwalk")
        try FileManager.default.createDirectory(at: filledOutput, withIntermediateDirectories: false)
        let stray = filledOutput.appendingPathComponent("precious.txt")

        do {
            _ = try DeviceBundleTransfer.fetch(source: "x", to: filledOutput, copier: FakeCopier(bundle: bundle.url, dropping: stray))
            Issue.record("a directory that gained contents was replaced")
        } catch let error as DeviceTransferError {
            guard case let .copyFailed(reason) = error else {
                Issue.record("expected copyFailed, got \(error)")
                return
            }
            #expect(reason.contains(filledOutput.path))
        }

        #expect(FileManager.default.fileExists(atPath: stray.path))
        #expect(try leftovers(in: filled.url).isEmpty)
    }

    /// A copy that reports success but is missing an artefact the manifest names is torn, not a pass.
    @Test
    func aCopyMissingAnArtefactIsTornAndLeavesNothing() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let host = try TemporaryDirectory()
        let output = host.url.appendingPathComponent("walk.simwalk")
        let artefact = try #require(FakeCopier.files(of: bundle.url).first { $0.hasSuffix(".png") })

        do {
            _ = try DeviceBundleTransfer.fetch(source: "x", to: output, copier: FakeCopier(bundle: bundle.url, omitting: artefact))
            Issue.record("a bundle missing an artefact was accepted")
        } catch let error as DeviceTransferError {
            guard case .torn = error else {
                Issue.record("expected torn, got \(error)")
                return
            }
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try leftovers(in: host.url).isEmpty)
    }

    /// A complete copy reads back from the output path and leaves no staging directory.
    @Test
    func aCompleteCopyArrivesAtTheOutputAndLeavesNoStaging() throws {
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let host = try TemporaryDirectory()
        let output = host.url.appendingPathComponent("walk.simwalk")

        let fetched = try DeviceBundleTransfer.fetch(source: "x", to: output, copier: FakeCopier(bundle: bundle.url))

        #expect(fetched.url == output)
        #expect(fetched.manifest == bundle.manifest)
        #expect(try leftovers(in: host.url).isEmpty)
    }

    /// A check that throws refuses the bundle: its own error comes out, and nothing is left at the output or beside it.
    @Test
    func aCheckThatThrowsLeavesNothingAndPropagatesItsOwnError() throws {
        struct NotThisWalks: Error {}
        let source = try TemporaryDirectory()
        let bundle = try makeBundle(in: source)
        let host = try TemporaryDirectory()
        let output = host.url.appendingPathComponent("walk.simwalk")

        #expect(throws: NotThisWalks.self) {
            _ = try DeviceBundleTransfer.fetch(source: "x", to: output, copier: FakeCopier(bundle: bundle.url)) { _ in throw NotThisWalks() }
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try leftovers(in: host.url).isEmpty)
    }
}

extension DeviceBundleTransferTests {
    /// Copies the files of a real bundle into the destination in a fixed order, manifest first (the worst order for the guarantee), optionally stopping after `limit` files or leaving one out.
    struct FakeCopier: DeviceContainerCopying {
        let bundle: URL
        var limit: Int?
        var omitting: String?
        /// When set, the copy asserts it was not handed this path and that nothing exists there.
        var guardedOutput: URL?
        var makesIntermediates = true
        /// When set, a file written here as the copy starts, standing in for something that appeared meanwhile.
        var dropping: URL?

        init(bundle: URL, limit: Int? = nil, omitting: String? = nil, guarding output: URL? = nil, makesIntermediates: Bool = true, dropping: URL? = nil) {
            self.bundle = bundle
            self.limit = limit
            self.omitting = omitting
            guardedOutput = output
            self.makesIntermediates = makesIntermediates
            self.dropping = dropping
        }

        static func files(of bundle: URL) throws -> [String] {
            let all = try FileManager.default.subpathsOfDirectory(atPath: bundle.path).sorted()
            let regular = all.filter { path in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: bundle.appendingPathComponent(path).path, isDirectory: &isDirectory)
                return !isDirectory.boolValue
            }
            let manifest = regular.filter { $0 == CaptureBundleLayout.manifestFileName }
            return manifest + regular.filter { $0 != CaptureBundleLayout.manifestFileName }
        }

        func copy(source _: String, to destination: URL) throws {
            let fileManager = FileManager.default
            if let guardedOutput {
                guard destination != guardedOutput else { throw Violation(reason: "the copy was handed the output itself") }
                guard !fileManager.fileExists(atPath: guardedOutput.path) else { throw Violation(reason: "something existed at the output while copying") }
            }
            if let dropping {
                try Data("x".utf8).write(to: dropping)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: makesIntermediates)
            for (index, path) in try Self.files(of: bundle).enumerated() {
                if let limit, index >= limit {
                    throw Interrupted()
                }
                if path == omitting {
                    continue
                }
                let target = destination.appendingPathComponent(path)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: bundle.appendingPathComponent(path), to: target)
            }
        }
    }
}

extension DeviceBundleTransferTests.FakeCopier {
    struct Interrupted: Error {}

    /// The copy was asked to write where the staging guarantee says it must not.
    struct Violation: Error {
        let reason: String
    }
}
