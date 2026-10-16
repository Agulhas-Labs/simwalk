//
// Copyright © Agulhas Labs
//

import Foundation

/// The live state of one walk, as the progress file carries it (`Docs/SIMWALK-PROGRESS.md` §2): what a Claude Code mod polls to draw `running · Step 4/12 · login · 3✓ 0✗` while the tool call it is watching has not returned.
///
/// **The six keys a reader may rely on are the stored non-optionals**: `schemaVersion`, `tool`, `phase`, `pid`, `startedAt` and `updatedAt`. Everything else is optional and **omitted when `nil`** rather than written as `null` — the spec allows either, and an absent key costs a polling reader nothing to parse. Dates are written through ``Timestamp`` (ISO-8601 UTC with milliseconds) by ``encoder()``, and held already rounded to the millisecond so a file read back equals the value written.
public struct WalkProgress: Codable, Equatable, Sendable {
    /// The schema this build writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// The face that started the run: `walk`, `walk --dry-run` or `session`.
    public var tool: String
    public var phase: Phase
    /// The process that owns the run — a reader treats a non-terminal phase whose `pid` is dead as `idle` (§2), since an interrupted run usually dies without running any code.
    public var pid: Int32
    public private(set) var startedAt: Date
    public private(set) var updatedAt: Date
    public var device: Device?
    /// The bundle identifier of the app being walked.
    public var app: String?
    public var currentStep: CurrentStep?
    public var matches: Matches?
    /// The absolute path of the last screenshot the runner filed.
    public var lastScreenshotPath: String?
    public var summary: PhaseTimings?
    public var logPath: String?
    /// The result file, set in the same write that makes the phase terminal, once that file exists (§3).
    public var resultPath: String?
    public var error: String?

    public init(tool: String, phase: Phase, pid: Int32, startedAt: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.tool = tool
        self.phase = phase
        self.pid = pid
        self.startedAt = Timestamp.millisecondRounded(startedAt)
        updatedAt = self.startedAt
    }

    /// Stamps the moment this state is written.
    mutating func touch(at date: Date) {
        updatedAt = Timestamp.millisecondRounded(date)
    }

    /// The encoder the progress file is written with: compact, sorted keys, unescaped slashes (a path is read by a mod, not by a JSON-escaping parser), and ``Timestamp`` dates.
    public static func encoder() -> JSONEncoder {
        let encoder = CaptureBundle.encoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The matching decoder.
    public static func decoder() -> JSONDecoder {
        CaptureBundle.decoder()
    }
}

public extension WalkProgress {
    /// Where a walk is, in the order a walk takes them (§2).
    ///
    /// The host boots, installs, builds the runner and launches it; the runner walks; the host reads the bundle back. `done` and `failed` are terminal and stay until the next run.
    enum Phase: String, Codable, Equatable, Sendable, CaseIterable {
        case idle
        case booting
        case installing
        case building
        case launching
        case running
        case matching
        case done
        case failed

        /// Whether the run has ended — the two phases that persist until the next run overwrites them.
        public var isTerminal: Bool {
            switch self {
            case .done, .failed: true
            case .idle, .booting, .installing, .building, .launching, .running, .matching: false
            }
        }
    }

    /// The simulator the run is on.
    struct Device: Codable, Equatable, Sendable {
        public var name: String
        public var udid: String
        public var osVersion: String

        public init(name: String, udid: String, osVersion: String) {
            self.name = name
            self.udid = udid
            self.osVersion = osVersion
        }

        /// The device a manifest records, without the locale the progress file has no use for.
        public init(_ device: CaptureManifest.Device) {
            self.init(name: device.name, udid: device.udid, osVersion: device.osVersion)
        }
    }

    /// One **screen** of the walkbook — a step of the plan, not a tap.
    struct CurrentStep: Codable, Equatable, Sendable {
        /// 1-based.
        public var index: Int
        /// The number of screens the run executes; `nil` for `session`, where an agent drives ad hoc and a reader shows the index alone.
        public var total: Int?
        /// A short human line, such as `walk login`.
        public var action: String?
        /// The walkbook id of the screen.
        public var screen: String?

        public init(index: Int, total: Int? = nil, action: String? = nil, screen: String? = nil) {
            self.index = index
            self.total = total
            self.action = action
            self.screen = screen
        }
    }

    /// Screens counted by outcome, updated as each screen finishes rather than at the end.
    ///
    /// "Passed" is the screen reached and captured as the walkbook said — **a walk compares no screenshots** — so `passed` counts `captured` alone and `failed` every other outcome.
    struct Matches: Codable, Equatable, Sendable {
        /// The screens the run executes.
        public var planned: Int
        public var passed: Int
        public var failed: Int
        public var pending: Int

        /// A run about to execute `planned` screens, none of them finished.
        public init(planned: Int) {
            self.planned = planned
            passed = 0
            failed = 0
            pending = planned
        }

        /// Counts one finished screen under the outcome it was recorded with.
        public mutating func record(_ outcome: ScreenOutcome) {
            if case .captured = outcome {
                passed += 1
            } else {
                failed += 1
            }
            pending = max(0, planned - passed - failed)
        }
    }
}

public extension WalkProgress {
    /// The runner taking the file over (§3): phase `running`, the first of `screenIDs` current, and `matches` planned at their count where the host left none.
    mutating func beginScreens(_ screenIDs: [String]) {
        phase = .running
        currentStep = Self.step(at: 0, of: screenIDs)
        if matches == nil {
            matches = Matches(planned: screenIDs.count)
        }
    }

    /// The screen at `position` (0-based) of `screenIDs` finished as `record`: counted, its first screenshot the last one filed — resolved against `bundleURL`, the bundle the runner writes — and the next screen current.
    ///
    /// **The next screen rides in this write** because it starts at the same instant: a separate, throttled step write for it would always land inside the 500 ms this one opened and be dropped, leaving a reader one screen behind for the whole walk. A screen that filed nothing (an unreachable one) leaves `lastScreenshotPath` naming the last screenshot that was filed.
    mutating func finishScreen(_ record: CaptureManifest.ScreenRecord, at position: Int, of screenIDs: [String], in bundleURL: URL) {
        if matches == nil {
            matches = Matches(planned: screenIDs.count)
        }
        matches?.record(record.outcome)
        if let capture = record.captures.first {
            lastScreenshotPath = CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: bundleURL).path
        }
        if let next = Self.step(at: position + 1, of: screenIDs) {
            currentStep = next
        }
    }

    /// The step for the screen at `position` (0-based) of `screenIDs`, 1-based as the file carries it; `nil` past the end.
    static func step(at position: Int, of screenIDs: [String]) -> CurrentStep? {
        guard screenIDs.indices.contains(position) else {
            return nil
        }
        return CurrentStep(index: position + 1, total: screenIDs.count, action: "walk \(screenIDs[position])", screen: screenIDs[position])
    }
}
