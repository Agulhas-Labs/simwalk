//
// Copyright © Agulhas Labs
//

import SimulatorServices

/// How the devices a walk creates boot: slim, with the services the app does not need switched off, or stock.
public enum WalkBootMode: Sendable, Equatable {
    case slim(SlimWalkBoot)
    case stock(WalkStockReason)

    /// Decides the boot. A requested stock boot never reads the declarations; a runtime without a profile is stock before they are read.
    public static func decide(
        stockRequested: Bool,
        runtimeIdentifier: String,
        osVersion: String,
        resolve: (String) -> ProfileResolution,
        declarations: () -> Result<ProjectDeclarations, UnreadableAppDeclarations>
    ) -> WalkBootMode {
        if stockRequested {
            return .stock(.requested)
        }
        let profile: ServiceProfile
        let source: ProfileSource
        switch resolve(runtimeIdentifier) {
        case .none:
            return .stock(.noProfile(osVersion: osVersion))
        case let .unreadable(url, reason):
            return .stock(.profileRefused(path: url.path, reason: reason))
        case let .found(found, foundSource):
            profile = found
            source = foundSource
        }
        switch declarations() {
        case let .failure(failure):
            return .stock(.unreadable(failure.reason))
        case let .success(found):
            let unmapped = found.unmapped
            if !unmapped.isEmpty {
                return .stock(.unmapped(unmapped))
            }
            return .slim(SlimWalkBoot(profile: profile, plan: profile.plan(keeping: found.capabilities), source: source))
        }
    }

    /// One line saying what was decided.
    public var text: String {
        switch self {
        case let .stock(reason):
            return "stock: \(reason.text)"
        case let .slim(boot):
            let kept = boot.plan.kept.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue) \($0.value.count)" }.joined(separator: ", ")
            let profile = boot.profile
            return "slim: \(boot.plan.disabled.count) of \(profile.services.count) services off (iOS \(profile.runtime.version), profile v\(profile.profileVersion), \(boot.source.text)), kept for the app: \(kept.isEmpty ? "nothing" : kept)"
        }
    }
}

extension ProfileSource {
    /// `bundled`, or `local` and the file the profile was read from.
    var text: String {
        switch self {
        case .bundled: "bundled"
        case let .local(url): "local \(url.path)"
        }
    }
}
