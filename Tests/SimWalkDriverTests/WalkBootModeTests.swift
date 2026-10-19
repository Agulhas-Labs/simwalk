//
// Copyright © Agulhas Labs
//

import SimulatorServices
@testable import SimWalkDriver
import Testing

/// Whether a walk's devices boot slim or stock is decided in a fixed order, and each decision says so in one line.
struct WalkBootModeTests {
    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    private static func service(_ label: String, _ disposition: Disposition) -> ServiceEntry {
        ServiceEntry(label: label, domain: .daemon, start: .keepAlive, ranAtBoot: true, peakFootprintMB: 10, cpuSeconds: 1, disposition: disposition)
    }

    /// Four services off, one of them serving HealthKit, and two the runtime keeps.
    private static let profile = ServiceProfile(
        profileVersion: 3,
        runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A1"),
        deviceType: "iPhone 17",
        generated: "fixture",
        method: ProfileMethod(costWindowSeconds: 1, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
        services: [
            service("gizmo.a", .disable), service("gizmo.b", .disable), service("gizmo.health", .disable), service("gizmo.push", .disable),
            service("gizmo.core", .core), service("gizmo.infra", .infrastructure),
        ],
        capabilities: [.healthKit: ["gizmo.health"], .pushNotifications: ["gizmo.push"]]
    )

    private static func decide(
        stock: Bool = false,
        profile: ServiceProfile? = profile,
        _ declarations: Result<ProjectDeclarations, UnreadableAppDeclarations>
    ) -> WalkBootMode {
        WalkBootMode.decide(
            stockRequested: stock, runtimeIdentifier: runtime, osVersion: "27.0",
            profileLookup: { $0 == runtime ? profile : nil }, declarations: { declarations }
        )
    }

    /// The plan keeps what the declared capabilities need, and the text counts what is off and what was kept.
    @Test
    func slimPlanKeepsWhatTheAppDeclares() {
        let declared = ProjectDeclarations(entitlements: ["com.apple.developer.healthkit"])

        let mode = Self.decide(.success(declared))

        #expect(mode == .slim(SlimWalkBoot(profile: Self.profile, plan: Self.profile.plan(keeping: [.healthKit]))))
        guard case let .slim(boot) = mode else { return }
        #expect(boot.plan.disabled == ["gizmo.a", "gizmo.b", "gizmo.push"])
        #expect(boot.plan.kept == [.healthKit: ["gizmo.health"]])
        #expect(mode.text == "slim: 3 of 6 services off (iOS 27.0, profile v3), kept for the app: healthKit 1")
    }

    /// An app that declares nothing the profile serves keeps nothing.
    @Test
    func slimTextSaysNothingWhenNothingIsKept() {
        let mode = Self.decide(.success(ProjectDeclarations()))

        #expect(mode.text == "slim: 4 of 6 services off (iOS 27.0, profile v3), kept for the app: nothing")
    }

    /// Kept capabilities are listed in name order.
    @Test
    func slimTextListsKeptCapabilitiesInNameOrder() {
        let declared = ProjectDeclarations(entitlements: ["aps-environment", "com.apple.developer.healthkit"])

        #expect(Self.decide(.success(declared)).text == "slim: 2 of 6 services off (iOS 27.0, profile v3), kept for the app: healthKit 1, pushNotifications 1")
    }

    /// `--stock` is stock without the declarations being read.
    @Test
    func stockRequestedNeverReadsTheDeclarations() {
        var reads = 0
        let mode = WalkBootMode.decide(
            stockRequested: true, runtimeIdentifier: Self.runtime, osVersion: "27.0",
            profileLookup: { _ in Self.profile }, declarations: { reads += 1
                return .success(ProjectDeclarations())
            }
        )

        #expect(mode == .stock(.requested))
        #expect(mode.text == "stock: --stock")
        #expect(reads == 0)
    }

    /// A runtime without a profile is stock before the declarations are read.
    @Test
    func noProfileIsStockBeforeTheDeclarationsAreRead() {
        var reads = 0
        let mode = WalkBootMode.decide(
            stockRequested: false, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-4", osVersion: "26.4",
            profileLookup: { _ in nil }, declarations: { reads += 1
                return .success(ProjectDeclarations())
            }
        )

        #expect(mode == .stock(.noProfile(osVersion: "26.4")))
        #expect(mode.text == "stock: no service profile for iOS 26.4")
        #expect(reads == 0)
    }

    /// Declarations that cannot be read are stock, with the reason.
    @Test
    func unreadableDeclarationsAreStock() {
        let mode = Self.decide(.failure(UnreadableAppDeclarations(reason: "Gizmo.app/Info.plist: no such file")))

        #expect(mode == .stock(.unreadable("Gizmo.app/Info.plist: no such file")))
        #expect(mode.text == "stock: the app's declarations could not be read (Gizmo.app/Info.plist: no such file)")
    }

    /// An app that declares what no rule maps is stock, naming the keys.
    @Test
    func unmappedDeclarationsAreStock() {
        let declared = ProjectDeclarations(entitlements: ["com.apple.developer.gizmo"], infoPlistKeys: ["NSGizmoUsageDescription"])

        let mode = Self.decide(.success(declared))

        #expect(mode == .stock(.unmapped(["NSGizmoUsageDescription", "com.apple.developer.gizmo"])))
        #expect(mode.text == "stock: the app declares what no rule maps (NSGizmoUsageDescription, com.apple.developer.gizmo)")
    }
}
