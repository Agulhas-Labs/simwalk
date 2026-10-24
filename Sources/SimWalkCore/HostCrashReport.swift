//
// Copyright © Agulhas Labs
//

import Foundation

/// One macOS crash report (`.ips`), read for the process it names and when it was captured (SimWalk#176).
///
/// A report is two JSON documents: a one-line header, then the body. The body's `procName`, `procPath`, `captureTime` (`yyyy-MM-dd HH:mm:ss.SSSS Z`) and, where present, `parentProc` and `coalitionName` are read, as macOS 27 writes them; the header is skipped. A simulator's crash reports land in the same directory as the Mac's own, and are told apart by ``isInSimulator``: a simulator's `xctest` runs from the platform inside Xcode (`…/iPhoneSimulator.platform/…/xctest`), not from under `CoreSimulator`, so the path alone missed it.
///
/// Pure — bytes in, a report out — and `nil` for anything unreadable, never a throw: a report that cannot be read is evidence of nothing.
public struct HostCrashReport: Equatable, Sendable {
    /// The report's file name, which is how an answer names it.
    public let fileName: String
    /// The crashed process's name.
    public let processName: String
    /// The crashed process's executable path.
    public let processPath: String
    /// The crashed process's parent, where the report names one: `launchd_sim` for a process in a simulator.
    public let parentProcess: String?
    /// The coalition the crashed process belonged to, where the report names one: `com.apple.CoreSimulator.SimDevice.<UDID>` for a simulator's.
    public let coalitionName: String?
    /// When the crash was captured.
    public let capturedAt: Date

    public init(fileName: String, processName: String, processPath: String, parentProcess: String? = nil, coalitionName: String? = nil, capturedAt: Date) {
        self.fileName = fileName
        self.processName = processName
        self.processPath = processPath
        self.parentProcess = parentProcess
        self.coalitionName = coalitionName
        self.capturedAt = capturedAt
    }

    /// Whether the crashed process ran inside a simulator rather than on the Mac: any one of its path under `CoreSimulator`, its path under a `Simulator.platform/`, its parent being `launchd_sim`, or its coalition being a `com.apple.CoreSimulator.SimDevice.` one.
    public var isInSimulator: Bool {
        processPath.contains("/CoreSimulator/")
            || processPath.contains("Simulator.platform/")
            || parentProcess == "launchd_sim"
            || coalitionName?.hasPrefix("com.apple.CoreSimulator.SimDevice.") == true
    }

    /// The report in `data`, named `fileName`, or `nil` when it is not one this can read.
    public static func parse(fileName: String, _ data: Data) -> HostCrashReport? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let body = try? JSONDecoder().decode(Body.self, from: Data(data[data.index(after: newline)...])),
              let capturedAt = captureTimeFormatter().date(from: body.captureTime)
        else { return nil }
        return HostCrashReport(fileName: fileName, processName: body.procName, processPath: body.procPath, parentProcess: body.parentProc, coalitionName: body.coalitionName, capturedAt: capturedAt)
    }
}

extension HostCrashReport {
    /// The part of a report's body that is read.
    private struct Body: Decodable {
        let procName: String
        let procPath: String
        let parentProc: String?
        let coalitionName: String?
        let captureTime: String
    }

    /// How a report's body spells `captureTime`: `2026-10-21 10:25:15.6053 +0100`.
    private static func captureTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
        return formatter
    }
}
