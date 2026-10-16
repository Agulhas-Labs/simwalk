//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `appBuildProvenance` (SimWalk#116): optional inside the current format, so a manifest without it means read back from the installed app.
struct CaptureManifestProvenanceTests {
    @Test
    func aManifestWithoutProvenanceDecodesNil() throws {
        let plain = CaptureBundleTests.manifest()
        let data = try CaptureBundle.encoder().encode(plain)
        #expect(!String(decoding: data, as: UTF8.self).contains("appBuildProvenance"))

        let decoded = try CaptureBundle.decoder().decode(CaptureManifest.self, from: data)

        #expect(decoded.appBuildProvenance == nil)
    }

    @Test
    func installedProvenanceRoundTrips() throws {
        var manifest = CaptureBundleTests.manifest()
        manifest.appBuildProvenance = .installed
        let data = try CaptureBundle.encoder().encode(manifest)
        #expect(String(decoding: data, as: UTF8.self).contains(#""appBuildProvenance" : "installed""#))

        let decoded = try CaptureBundle.decoder().decode(CaptureManifest.self, from: data)

        #expect(decoded.appBuildProvenance == .installed)
        #expect(BundleDiff.Build(decoded).appBuildProvenance == .installed)
    }
}
