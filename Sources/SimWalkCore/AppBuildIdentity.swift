//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// The build hash of an installed app — `WalkbookIdentity`'s counterpart for the binary.
///
/// A manifest's `appBuildHash` is what makes `ScreenOutcome.buildMismatch` possible at all: a capture whose installed app does not match the build the walk claims to validate refuses rather than silently validating a stale binary (Brief §2.1). Until this existed the field was whatever a caller passed, which meant in practice `"unknown"` — a manifest asserting provenance it did not have, and a refusal that could never fire.
///
/// **Taken over the executable, not the version string.** `CFBundleVersion` is authored: two genuinely different binaries share one all day during development, which is exactly the window a walk is run in. Hashing the Mach-O means the hash changes when the thing being validated changes, which is the only property that makes the refusal worth having. Read from the *installed* bundle on the device, because the question is what is about to be walked, never what a caller believes it installed.
public struct AppBuildIdentity {
    /// What a walk on a physical device records as the app's build.
    ///
    /// The installed app cannot be hashed from the Mac (SimWalk#116), so this names no build: two bundles carrying it are not known to be of the same one.
    public static var unreadOnDevice: String {
        "device-unread"
    }

    /// `buildHash` as an answer prints it: cut to ``ShortHash/digits``, or `unread (device)` for the placeholder.
    public static func printed(_ buildHash: String) -> String {
        buildHash == unreadOnDevice ? "unread (device)" : ShortHash.of(buildHash)
    }

    /// The hex SHA-256 of the app's executable.
    public static func hash(ofAppAt appPath: String, fileManager: FileManager = .default) throws -> String {
        let bundleURL = URL(fileURLWithPath: appPath)
        let executableURL = try executable(in: bundleURL, fileManager: fileManager)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: executableURL)
        } catch {
            throw AppBuildIdentityError.unreadableExecutable(path: executableURL.path, reason: error.localizedDescription)
        }
        defer { try? handle.close() }

        // Streamed rather than read whole: an app binary runs to tens of megabytes and there is no reason
        // for a walk's provenance step to hold one in memory.
        var digest = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The `CFBundleIdentifier` of the `.app` at `appPath`, from its own `Info.plist`.
    public static func bundleIdentifier(ofAppAt appPath: String) throws -> String {
        let bundleURL = URL(fileURLWithPath: appPath)
        guard let identifier = infoPlist(of: bundleURL)?["CFBundleIdentifier"] as? String else {
            throw AppBuildIdentityError.notAnApp(path: bundleURL.path)
        }
        return identifier
    }

    private static func infoPlist(of bundleURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// The executable named by the bundle's own `Info.plist`, rather than guessed from the directory name.
    private static func executable(in bundleURL: URL, fileManager: FileManager) throws -> URL {
        guard let name = infoPlist(of: bundleURL)?["CFBundleExecutable"] as? String else {
            throw AppBuildIdentityError.notAnApp(path: bundleURL.path)
        }
        let executableURL = bundleURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw AppBuildIdentityError.unreadableExecutable(path: executableURL.path, reason: "the bundle names it but it is not there")
        }
        return executableURL
    }
}
