//
// Copyright © Agulhas Labs
//

import SimulatorServices

/// A slim boot decided for a walk: the runtime's measured profile and the plan that keeps what the app declares.
public struct SlimWalkBoot: Sendable, Equatable {
    public let profile: ServiceProfile
    public let plan: SlimPlan
    /// Where the profile came from: shipped with the library, or measured on this machine.
    public let source: ProfileSource

    public init(profile: ServiceProfile, plan: SlimPlan, source: ProfileSource = .bundled) {
        self.profile = profile
        self.plan = plan
        self.source = source
    }
}
