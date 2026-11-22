//
// Copyright © Agulhas Labs
//

import Foundation

// Host-only, as `UsageLog.standard` is: `homeDirectoryForCurrentUser` is unavailable on iOS, where `~` is an app container.
#if os(macOS)
/// Where the user's home, this tool's home and sift's home are, resolved from an injected environment so a test harness can run the whole install inside a scratch directory.
///
/// **This is the one place the account's home is read**, from the password database: `homeDirectoryForCurrentUser` ignores `HOME` but follows `CFFIXED_USER_HOME`, so it is not the account's under a harness that sets that. Every path built from the user's home goes through here, and the machine-wide coordination state through ``account()``. A relative or empty variable is ignored, as sift ignores a relative `SIFT_HOME`.
public struct HomeDirectories {
    /// The variable that moves `~/.simwalk`.
    public static var simwalkVariable: String {
        "SIMWALK_HOME"
    }

    /// The variable that moves sift's `~/.sift`, read by sift itself and so by the status-line shim's location.
    public static var siftVariable: String {
        "SIFT_HOME"
    }

    /// `CFFIXED_USER_HOME` when it is an absolute path, else `HOME` when it is, else the account's home directory — sift's `SiftPaths.userHome` order, and the variable a test already isolates a process with.
    public static func user(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = absolute(environment["CFFIXED_USER_HOME"]) ?? absolute(environment["HOME"]) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return accountHome()
    }

    /// The account's own home directory, from the password database, which no environment variable moves (`CFFIXED_USER_HOME` included).
    public static func accountHome() -> URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `<account home>/.simwalk`, where state that coordinates processes across the machine lives (leases, live sessions, the Mirroring lock): no environment variable moves it, `CFFIXED_USER_HOME` included, so a process under a scratch home still sees the user's device leases.
    public static func account() -> URL {
        accountHome().appendingPathComponent(".simwalk", isDirectory: true)
    }

    /// `<account home>/Library/Logs/DiagnosticReports`, where the Mac writes its crash reports, a simulator app's among them (SimWalk#243): the system writes them there whatever `HOME` says.
    public static func diagnosticReports() -> URL {
        accountHome().appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// `SIMWALK_HOME` when it is an absolute path, else `<user home>/.simwalk`.
    public static func simwalk(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = absolute(environment[simwalkVariable]) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return user(environment: environment).appendingPathComponent(".simwalk", isDirectory: true)
    }

    /// `SIFT_HOME` when it is an absolute path, else `<user home>/.sift`.
    public static func sift(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = absolute(environment[siftVariable]) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return user(environment: environment).appendingPathComponent(".sift", isDirectory: true)
    }

    private static func absolute(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/") else { return nil }
        return value
    }
}
#endif
