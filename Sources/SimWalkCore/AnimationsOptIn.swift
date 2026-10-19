//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a simulator walk launches the app with UIKit animations off (SimWalk#154), and how the library that does it reaches the app.
///
/// **Off by default**, so screens settle sooner and captures do not depend on an animation's phase. A walk keeps them on when asked (`--animations`) or when it records motion, since motion and settle time must match what users see. The host builds the library (the core cannot import `SimulatorAnimations`: the runner links this package, and swift-fieldwork is macOS-only) and writes ``hostEnvironmentKey``; the runner reads it back through ``library(in:)`` and inserts it into the app's launch environment with ``inserting(_:into:)``. Both ends name the key and the decision here, so a typo on either side fails a test in `swift test`.
///
/// SwiftUI `withAnimation` is not affected; only UIKit's `UIView.setAnimationsEnabled`.
public struct AnimationsOptIn {
    /// The runner-side variable: the path of the animations-off library; absent means the app launches without it.
    public static var environmentKey: String {
        "SIMWALK_ANIMATIONS_OFF_LIBRARY"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``environmentKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + environmentKey
    }

    /// The variable the animations-off library itself reads (`on` keeps animations on); a walkbook state may not set it, because a walk has one animation state.
    public static var libraryEnvironmentKey: String {
        "SIMWALK_ANIMATIONS"
    }

    /// Why a state's `environment` may not name ``libraryEnvironmentKey``.
    public static var stateEnvironmentRefusal: String {
        "a state's environment cannot set \(libraryEnvironmentKey): a walk has one animation state; run it with --animations to keep animations on"
    }

    /// The variable dyld reads for libraries to insert into a launched process.
    public static var insertLibrariesKey: String {
        "DYLD_INSERT_LIBRARIES"
    }

    /// The library path in the runner's `environment`; `nil` when absent or empty.
    public static func library(in environment: [String: String]) -> String? {
        guard let path = environment[environmentKey], !path.isEmpty else { return nil }
        return path
    }

    /// What the runner records in the manifest: `.off` when ``library(in:)`` is present, since the app is then launched with the library inserted, else `.on`. A device walk's runner never has the key.
    public static func recorded(in environment: [String: String]) -> CaptureManifest.Animations {
        library(in: environment) == nil ? .enabled : .disabled
    }

    /// `environment` with `library` inserted into `DYLD_INSERT_LIBRARIES`: unchanged for `nil`, appended after any existing value with `:`.
    ///
    /// The same rule as swift-fieldwork's `AnimationsOffLibrary.insertingLibrary`, restated because the core cannot import it.
    public static func inserting(_ library: String?, into environment: [String: String]) -> [String: String] {
        guard let library else { return environment }
        var inserted = environment
        if let existing = environment[insertLibrariesKey], !existing.isEmpty {
            inserted[insertLibrariesKey] = existing + ":" + library
        } else {
            inserted[insertLibrariesKey] = library
        }
        return inserted
    }

    /// `.keptOn(.asked)` when `animations`; `.keptOn(.motion)` when the walk is run with `--motion` or any executed screen (all of them unless `selected` names some) records motion, by `"motion": true` or a motion budget; otherwise `.off`.
    public static func decision(for book: Walkbook, screens selected: [String], animations: Bool, motion: Bool) -> Decision {
        if animations {
            return .keptOn(.asked)
        }
        if motion {
            return .keptOn(.motion)
        }
        let executed = selected.isEmpty ? book.screens : book.screens.filter { selected.contains($0.id) }
        let recordsMotion = executed.contains { $0.motion == true || $0.budgets?.hasMotionBudget == true }
        return recordsMotion ? .keptOn(.motion) : .off
    }
}

public extension AnimationsOptIn {
    enum Decision: Equatable {
        case off
        case keptOn(Reason)
    }

    enum Reason: Equatable {
        /// `--animations` asked for them.
        case asked
        /// The walk records motion, so settle time and motion must be what users see.
        case motion
    }
}
