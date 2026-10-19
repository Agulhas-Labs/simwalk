//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `systemTap` that saw no sheet on a device that booted slim says so, with the count, the capabilities and the way to walk stock; every other refusal is as it was.
struct SlimDeviceRefusalTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let slim = SlimDevice(servicesOff: 94, capabilities: ["location", "healthKit"])
    private static var clause: String {
        "; the device has 94 launchd services set off, among them those serving healthKit, location — a sheet whose service is off never appears: walk again with --stock to rule that out"
    }

    private static var bare: String {
        "; the device has 94 launchd services set off — a sheet whose service is off never appears: walk again with --stock to rule that out"
    }

    private static func window(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "RouteFixture", children: [AXNode(type: "Window", frame: screen, children: content)])
    }

    private static var scope: SystemSheetScope {
        SystemSheetScope(baseline: window([]))
    }

    @Test
    func aRefusalThatSawNoSheetEndsWithTheSlimClause() {
        let plain = Self.scope.refusal(for: "Allow", passedOverAppOwn: false)
        let slimmed = Self.scope.refusal(for: "Allow", passedOverAppOwn: false, slim: Self.slim)

        #expect(slimmed == plain + Self.clause)
        #expect(plain.hasSuffix("a sheet already answered is not asked again"))
    }

    @Test
    func aRefusalAtLaunchEndsWithTheSlimClause() {
        let launch = SystemSheetScope.admittingAll(of: Self.window([]))
        let plain = launch.refusal(for: "Allow", passedOverAppOwn: false)

        #expect(launch.refusal(for: "Allow", passedOverAppOwn: false, slim: Self.slim) == plain + Self.clause)
    }

    @Test
    func aFreshBootNamesTheBootThenTheSlimClause() {
        let plain = Self.scope.refusal(for: "Allow", passedOverAppOwn: false, bootAge: 70)
        let slimmed = Self.scope.refusal(for: "Allow", passedOverAppOwn: false, bootAge: 70, slim: Self.slim)
        let launch = SystemSheetScope.admittingAll(of: Self.window([]))
        let launched = launch.refusal(for: "Allow", passedOverAppOwn: false, bootAge: 70)

        #expect(slimmed == plain + Self.clause)
        #expect(slimmed.contains("the device booted 70 s ago"))
        #expect(launch.refusal(for: "Allow", passedOverAppOwn: false, bootAge: 70, slim: Self.slim) == launched + Self.clause)
    }

    @Test
    func withNoCapabilityKnownTheClauseCountsOnly() {
        let counted = SlimDevice(servicesOff: 94, capabilities: [])
        let plain = Self.scope.refusal(for: "Allow", passedOverAppOwn: false)

        #expect(Self.scope.refusal(for: "Allow", passedOverAppOwn: false, slim: counted) == plain + Self.bare)
    }

    @Test
    func theAmbiguousRefusalIsUnchanged() {
        let allow = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 700, width: 361, height: 50), label: "Allow", identifier: "UIA.Health.Allow.Button")
        let scope = SystemSheetScope(baseline: Self.window([allow]))

        #expect(scope.refusal(for: "Allow", passedOverAppOwn: false, slim: Self.slim) == scope.refusal(for: "Allow", passedOverAppOwn: false))
    }

    @Test
    func aSearchThatSawNoSheetCarriesTheClause() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))
        let found: Int? = search.poll(home, springBoardShowedSheet: false) { _ in nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: nil, slim: Self.slim).reason == search.refusal(bootAge: nil).reason + Self.clause)
    }

    @Test
    func aSlimDeviceRoundTripsThroughItsEnvironmentValue() {
        #expect(Self.slim.environmentValue == "94;healthKit,location")
        #expect(SlimDevice.hostEnvironmentKey == "TEST_RUNNER_SIMWALK_SLIM_DEVICE")
        for device in [Self.slim, SlimDevice(servicesOff: 7, capabilities: [])] {
            #expect(SlimDevice.read(in: [SlimDevice.runnerKey: device.environmentValue]) == device)
        }
    }

    @Test(arguments: ["", "94", "x;healthKit", "0;healthKit", "-3;", ";healthKit", "94;healthKit,,location", "94;healthKit,"])
    func aMalformedValueReadsAsNotSlim(value: String) {
        #expect(SlimDevice.read(in: [SlimDevice.runnerKey: value]) == nil)
        #expect(SlimDevice.read(in: [:]) == nil)
    }
}
