//
// Copyright © Agulhas Labs
//

import Foundation

/// Copies a path inside the runner's data container on a physical device to a host path.
///
/// A seam rather than a call to `devicectl` so ``DeviceBundleTransfer`` can be tested against a copy that stops part-way. An implementation may leave whatever it had copied at `destination` when it throws; the caller does not trust it.
public protocol DeviceContainerCopying {
    func copy(source: String, to destination: URL) throws
}
