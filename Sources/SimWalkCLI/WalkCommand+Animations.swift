//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorAnimations
import SimWalkCore
import SimWalkDriver

extension WalkCommand {
    /// Builds, or finds already built, the animations-off library and names its file (SimWalk#154).
    typealias AnimationsLibrary = () throws -> URL

    /// The library a simulator walk launches the app with: cached under `$SIMWALK_HOME/libraries` (`~/.simwalk/libraries`), compiled on the first use of a build of it.
    ///
    /// Only the faces a person or an agent drives pass this; every other entry takes `nil`, which launches the app untouched, so a test never compiles anything.
    static func standardAnimationsLibrary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        compile: @escaping AnimationsOffLibrary.Compile = { try Subprocess.run($0, $1, deadline: 120) }
    ) -> AnimationsLibrary {
        {
            let directory = HomeDirectories.simwalk(environment: environment).appendingPathComponent("libraries", isDirectory: true)
            return try AnimationsOffLibrary(environmentVariable: AnimationsOptIn.libraryEnvironmentKey, directory: directory).built(compile: compile)
        }
    }

    /// What this simulator walk does about animations and the library path to hand the runner, or `nil` for both when `library` is `nil`.
    ///
    /// A dry run captures nothing, so it keeps animations only when asked: the motion rule is for what a capture records. A library that cannot be built fails the walk before anything boots.
    func animationsPlan(for book: Walkbook, library: AnimationsLibrary?) throws -> (decision: AnimationsOptIn.Decision, path: String?)? {
        guard let library else { return nil }
        let decision = dryRun
            ? (animations ? AnimationsOptIn.Decision.keptOn(.asked) : .off)
            : AnimationsOptIn.decision(for: book, screens: screens, animations: animations, motion: motion)
        guard decision == .off else { return (decision, nil) }
        return try (decision, Self.builtLibrary(library).path)
    }

    /// The library `library` builds, or ``AnimationsLibraryError`` naming why not: the one failure text and classification a walk and a session start share.
    static func builtLibrary(_ library: AnimationsLibrary) throws -> URL {
        do {
            return try library()
        } catch {
            throw AnimationsLibraryError(reason: (error as? AnimationsOffLibraryError).map(reason) ?? error.localizedDescription)
        }
    }

    private static func reason(of error: AnimationsOffLibraryError) -> String {
        switch error {
        case let .notBuilt(reason), let .invalidEnvironmentVariable(reason): reason
        }
    }

    /// The answer's one line about animations on a simulator walk; `nil` when they were asked for (nothing to explain) or nothing was decided.
    static func animationsNote(for decision: AnimationsOptIn.Decision?) -> String? {
        switch decision {
        case .off: "animations: UIKit off in the app under walk (SwiftUI animations still run); --animations keeps them"
        case .keptOn(.motion): "animations: kept on, because this walk records motion"
        case .keptOn(.asked), nil: nil
        }
    }

    /// The library could not be built, so the walk is refused before anything boots.
    struct AnimationsLibraryError: Error, CustomStringConvertible, UsageFailureClassifiable {
        let reason: String

        var description: String {
            "the animations-off library could not be built: \(reason); --animations walks without it"
        }

        var usageFailureKind: UsageFailureKind {
            .runnerFailed
        }
    }
}
