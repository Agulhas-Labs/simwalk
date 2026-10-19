//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// Reads what an installed `.app` declares: the entitlements embedded in its executable and the keys of its Info.plist.
///
/// The entitlements live in the executable's `__TEXT,__entitlements` section as an XML property list. A built app carries no StoreKit configuration, which is an Xcode scheme setting, so that declaration is always absent.
public struct AppDeclarations {
    /// The declarations of the app at `appPath`, or why they could not be read.
    public static func read(appPath: String) -> Result<ProjectDeclarations, UnreadableAppDeclarations> {
        let app = URL(fileURLWithPath: appPath)
        let name = app.lastPathComponent
        do {
            let infoName = "\(name)/Info.plist"
            let info = try contents(of: app.appendingPathComponent("Info.plist"), shownAs: infoName)
            let plist: [String: Any]
            let infoKeys: Set<String>
            do {
                infoKeys = try ProjectDeclarations.keys(ofPlist: info)
                plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any] ?? [:]
            } catch {
                throw UnreadableAppDeclarations(reason: "\(infoName): not a property list")
            }
            guard let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty else {
                throw UnreadableAppDeclarations(reason: "\(infoName): no CFBundleExecutable")
            }
            let executableName = "\(name)/\(executable)"
            let image = try contents(of: app.appendingPathComponent(executable), shownAs: executableName)
            guard let section = try MachOImage(image).section(segment: "__TEXT", name: "__entitlements", shownAs: executableName) else {
                return .success(declarations(entitlements: [], infoKeys: infoKeys, plist: plist))
            }
            let entitlements: Set<String>
            do {
                entitlements = try ProjectDeclarations.keys(ofPlist: section)
            } catch {
                throw UnreadableAppDeclarations(reason: "\(executableName): the entitlements section is not a property list")
            }
            return .success(declarations(entitlements: entitlements, infoKeys: infoKeys, plist: plist))
        } catch let failure as UnreadableAppDeclarations {
            return .failure(failure)
        } catch {
            return .failure(UnreadableAppDeclarations(reason: "\(name): \(error.localizedDescription)"))
        }
    }

    private static func declarations(entitlements: Set<String>, infoKeys: Set<String>, plist: [String: Any]) -> ProjectDeclarations {
        let modes = Set((plist["UIBackgroundModes"] as? [Any] ?? []).compactMap { $0 as? String })
        return ProjectDeclarations(entitlements: entitlements, infoPlistKeys: infoKeys, storeKitConfiguration: false, backgroundModes: modes)
    }

    private static func contents(of url: URL, shownAs name: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UnreadableAppDeclarations(reason: "\(name): no such file")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw UnreadableAppDeclarations(reason: "\(name): \(error.localizedDescription)")
        }
    }
}
