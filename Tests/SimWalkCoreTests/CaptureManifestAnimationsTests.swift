//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `animations` (SimWalk#154): optional inside the current format, so a manifest without it means the walk ran with animations on, and `bundle diff` refuses to compare across the two states.
struct CaptureManifestAnimationsTests {
    @Test
    func aManifestWithoutTheFieldWritesNoKeyAndDecodesNilAsOn() throws {
        let data = try CaptureBundle.encoder().encode(CaptureBundleTests.manifest())
        #expect(!String(decoding: data, as: UTF8.self).contains("animations"))

        let decoded = try CaptureBundle.decoder().decode(CaptureManifest.self, from: data)

        #expect(decoded.animations == nil)
        #expect(decoded.recordedAnimations == .enabled)
    }

    @Test
    func offRoundTrips() throws {
        var manifest = CaptureBundleTests.manifest()
        manifest.animations = .disabled
        let data = try CaptureBundle.encoder().encode(manifest)
        #expect(String(decoding: data, as: UTF8.self).contains(#""animations" : "off""#))

        let decoded = try CaptureBundle.decoder().decode(CaptureManifest.self, from: data)

        #expect(decoded.animations == .disabled)
        #expect(decoded.recordedAnimations == .disabled)
    }

    @Test
    func theRefusalIsNilForTheSameStateAndForUnrecordedAgainstOn() {
        let unrecorded = CaptureBundleTests.manifest()
        var enabledManifest = unrecorded
        enabledManifest.animations = .enabled
        var disabledManifest = unrecorded
        disabledManifest.animations = .disabled

        #expect(BundleDiff.animationsRefusal(run: disabledManifest, reference: disabledManifest) == nil)
        #expect(BundleDiff.animationsRefusal(run: enabledManifest, reference: enabledManifest) == nil)
        #expect(BundleDiff.animationsRefusal(run: enabledManifest, reference: unrecorded) == nil)
        #expect(BundleDiff.animationsRefusal(run: unrecorded, reference: enabledManifest) == nil)
    }

    @Test
    func theRefusalNamesEachDirection() {
        let unrecorded = CaptureBundleTests.manifest()
        var enabledManifest = unrecorded
        enabledManifest.animations = .enabled
        var disabledManifest = unrecorded
        disabledManifest.animations = .disabled

        #expect(BundleDiff.animationsRefusal(run: disabledManifest, reference: enabledManifest) == "bundle diff refused: the reference was captured with animations on and the run with animations off, so their motion and settle figures differ for that reason alone; capture both in one state (--animations keeps animations on, and a walk that records motion or runs on a device keeps them on regardless)")
        #expect(BundleDiff.animationsRefusal(run: enabledManifest, reference: disabledManifest) == "bundle diff refused: the reference was captured with animations off and the run with animations on, so their motion and settle figures differ for that reason alone; capture both in one state (--animations keeps animations on, and a walk that records motion or runs on a device keeps them on regardless)")
        #expect(BundleDiff.animationsRefusal(run: disabledManifest, reference: unrecorded) == "bundle diff refused: the reference was captured with animations on (recorded before SimWalk recorded it) and the run with animations off, so their motion and settle figures differ for that reason alone; capture both in one state (--animations keeps animations on, and a walk that records motion or runs on a device keeps them on regardless)")
    }
}
