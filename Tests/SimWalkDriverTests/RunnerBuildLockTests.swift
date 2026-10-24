//
// Copyright © Agulhas Labs
//

import Foundation
import os
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// One runner build at a time per build directory (SimWalk#242): walks started together on a cold build collided inside one derived-data directory, on package resolution or on `xcodebuild`'s build database (`database is locked`).
struct RunnerBuildLockTests {
    /// Two runs building into one directory at the same moment take turns: `xcodebuild` never runs twice at once there, and both builds go through.
    @Test
    func twoBuildsIntoOneDirectoryNeverOverlap() throws {
        let scratch = try TemporaryDirectory()
        let derivedData = scratch.url.appendingPathComponent("build", isDirectory: true).path
        let state = OSAllocatedUnfairLock(initialState: (running: 0, most: 0, calls: 0))
        let failures = OSAllocatedUnfairLock<[String]>(initialState: [])

        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            let shell = Shell(script: { _, _, _ in
                state.withLock { now in
                    now.running += 1
                    now.most = max(now.most, now.running)
                    now.calls += 1
                }
                Thread.sleep(forTimeInterval: 0.5)
                state.withLock { $0.running -= 1 }
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            })
            let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: derivedData, shell: shell)
            do {
                try runner.build(for: Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true))
            } catch {
                failures.withLock { $0.append(error.localizedDescription) }
            }
        }

        #expect(failures.withLock(\.self).isEmpty)
        #expect(state.withLock(\.calls) == 2)
        #expect(state.withLock(\.most) == 1)
    }

    /// A build that finds another run building there says it is waiting, once, and runs `xcodebuild` only after that run lets go.
    @Test
    func aBuildThatHasToWaitSaysSoAndBuildsOnlyOnceTheOtherRunIsDone() throws {
        let scratch = try TemporaryDirectory()
        let derivedData = scratch.url.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        // The other run, holding the directory as a build does.
        let other = open(derivedData.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        defer { close(other) }
        try #require(flock(other, LOCK_EX) == 0)

        let calls = OSAllocatedUnfairLock(initialState: 0)
        let notes = OSAllocatedUnfairLock<[String]>(initialState: [])
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let shell = Shell(script: { _, _, _ in
                calls.withLock { $0 += 1 }
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            })
            let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: derivedData.path, shell: shell)
            try? runner.build(for: Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)) { line in
                notes.withLock { $0.append(line) }
                waiting.signal()
            }
            finished.signal()
        }

        try #require(waiting.wait(timeout: .now() + 30) == .success)
        #expect(calls.withLock(\.self) == 0)
        flock(other, LOCK_UN)
        try #require(finished.wait(timeout: .now() + 30) == .success)

        #expect(notes.withLock(\.self) == ["waiting for another run's runner build"])
        #expect(calls.withLock(\.self) == 1)
    }
}
