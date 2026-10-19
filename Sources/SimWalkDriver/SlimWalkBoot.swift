//
// Copyright © Agulhas Labs
//

import SimulatorServices

/// A slim boot decided for a walk: the runtime's measured profile and the plan that keeps what the app declares.
public struct SlimWalkBoot: Sendable, Equatable {
    public let profile: ServiceProfile
    public let plan: SlimPlan

    public init(profile: ServiceProfile, plan: SlimPlan) {
        self.profile = profile
        self.plan = plan
    }
}
