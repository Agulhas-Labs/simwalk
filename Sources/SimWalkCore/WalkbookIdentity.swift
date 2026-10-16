//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// The content hash of a walkbook — build-mismatch's counterpart for the plan rather than the binary.
///
/// A manifest already says which build it validated; without this it cannot say which *walk* produced it. Two bundles of "the field walk" a week apart may have been produced by different plans, and comparing them as though they were the same walk is the same class of mistake as validating a stale binary. The hash is taken over the canonical encoding of the decoded model, not the file's bytes, so reformatting the JSON or reordering its keys does not read as a changed plan while a changed route does.
public struct WalkbookIdentity {
    /// The hex SHA-256 of the walkbook's canonical encoding.
    public static func hash(of walkbook: Walkbook) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = try SHA256.hash(data: encoder.encode(walkbook))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `walkbook` is the plan that produced `manifest`: the whole walkbook hashes to the manifest's hash, or the manifest's own screens narrow it to a subset that does.
    ///
    /// A `--screens` walk records the hash of the subset it ran (`WalkbookSubset`), so comparing the full walkbook's hash alone would call an unchanged walkbook changed. Narrowing goes through the same `WalkbookSubset.narrow` the walk used; a screen the walkbook lacks means it is not that plan.
    public static func isPlan(_ walkbook: Walkbook, of manifest: CaptureManifest) throws -> Bool {
        if try hash(of: walkbook) == manifest.walkbookHash {
            return true
        }
        guard let subset = try? WalkbookSubset.narrow(walkbook, to: manifest.screens.map(\.id)) else {
            return false
        }
        return try hash(of: subset) == manifest.walkbookHash
    }
}
