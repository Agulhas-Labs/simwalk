//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Brings a capture bundle back from a physical device's runner container, keeping the writer's manifest-last guarantee across the copy.
///
/// **The output path appears only by a rename after a complete copy that reads back and passes the caller's check.** The copy goes into a hidden sibling of `output` (same directory, so the rename is atomic); `CaptureBundle.read` then refuses a missing or torn manifest and any artefact the manifest names that did not arrive. Only a bundle that passes is renamed into place; a check that throws (is this bundle this walk's?) removes the staging exactly as a torn copy does, and its error propagates unwrapped. A copy interrupted at any point — in any order the copier wrote its files — therefore leaves nothing at `output`: a reader sees an absent bundle, never a partial one that could pass for a walk.
///
/// **Residual:** a file the copier reports as copied but that arrived short would still pass, because the manifest carries no per-artefact byte counts to check it against.
public struct DeviceBundleTransfer {
    /// Copies `source` from the device into `output` and returns the bundle read back from there.
    ///
    /// `check` sees the bundle read from staging, before the rename; if it throws, nothing reaches `output`.
    public static func fetch(
        source: String,
        to output: URL,
        copier: DeviceContainerCopying,
        fileManager: FileManager = .default,
        check: (CaptureBundle) throws -> Void = { _ in }
    ) throws -> CaptureBundle {
        try CaptureBundleWriter.requireFresh(output, fileManager: fileManager)

        do {
            try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw DeviceTransferError.copyFailed(reason: "the output's directory could not be created: \(error.localizedDescription)")
        }

        let stem = output.deletingPathExtension().lastPathComponent
        let token = UUID().uuidString.prefix(8).lowercased()
        let staging = output.deletingLastPathComponent()
            .appendingPathComponent(".\(stem).partial-\(token).\(CaptureBundleLayout.directoryExtension)", isDirectory: true)

        do {
            do {
                try copier.copy(source: source, to: staging)
            } catch let error as DeviceTransferError {
                throw error
            } catch {
                throw DeviceTransferError.copyFailed(reason: "\(error)")
            }
            let staged: CaptureBundle
            do {
                staged = try CaptureBundle.read(at: staging, fileManager: fileManager)
            } catch {
                throw DeviceTransferError.torn(reason: "\(error)")
            }
            try check(staged)
            // An empty directory at `output` passed `requireFresh`; a rename onto it would fail. `rmdir` removes it only while it is still empty: if something appeared there during the copy, it is not ours to delete.
            if fileManager.fileExists(atPath: output.path), rmdir(output.path) != 0 {
                throw DeviceTransferError.copyFailed(reason: "\(output.path) gained contents while the bundle was copied, and was left alone")
            }
            do {
                try fileManager.moveItem(at: staging, to: output)
            } catch {
                throw DeviceTransferError.copyFailed(reason: "the copied bundle could not be moved into place: \(error.localizedDescription)")
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return try CaptureBundle.read(at: output, fileManager: fileManager)
    }
}
