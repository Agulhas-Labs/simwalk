//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a dry run's route-probe report as an answer in the contract's shape — what `walk --dry-run` prints.
///
/// **A drifted route is a shortfall, and the verdict says so.** The field report behind this (SimWalk#1 item 4) was three routes of a field walkbook that no longer matched the app under them, found only by walking; a dry run that reported them and exited 0 would be the same silent pass one level earlier. Each route that did not resolve is a qualification, which is exit 2.
///
/// **A route probed under one set of launch conditions is not claimed for another (SimWalk#36, extended SimWalk#44).** The runner launches each screen once, under its first state's theme, Dynamic Type size, locale, arguments and environment, and any of those can change what a screen shows: a screen walked under `en` and `de`, or under one argument list and another, whose route resolved under the first has said nothing about the rest. Each such screen is a qualification, so a clean exit never claims more than was probed.
///
/// **Every drifted line names the step and the label it looked for**, with the runner's own reason — what the label matched, and what the tap did — because "route drifted" alone sends an author to re-read the whole route. The steps after it are named as not reached, so a later step that also drifted is not taken to have been checked.
public struct RouteProbeSummary {
    private let report: RouteProbeReport
    private let launchConditionGaps: [LaunchConditionGap]
    private let qualifications: [String]
    private let notes: [String]

    /// - Parameters:
    ///   - report: the dry run's output.
    ///   - launchConditionGaps: the screens whose states name a locale, argument list or environment the route was not probed under — `LaunchConditionGap.all(in:)` of the walkbook the runner was handed.
    ///   - qualifiedBy: facts about the *run* the report cannot carry — a runner failure it survived, a device not handed back.
    ///   - notes: lines printed under the residue: what the run handed the device back in.
    public init(_ report: RouteProbeReport, launchConditionGaps: [LaunchConditionGap] = [], qualifiedBy qualifications: [String] = [], notes: [String] = []) {
        self.report = report
        self.launchConditionGaps = launchConditionGaps
        self.qualifications = qualifications
        self.notes = notes
    }

    /// The answer, ready for a face to print or a log to record.
    ///
    /// No saving line: a dry run stands in for no material a reader would otherwise have opened — nothing was captured — and the contract prices an absence as no line rather than as a saving of zero.
    public func answer() -> Answer {
        var residue = report.probes.enumerated().map { Self.probeLine($0.element, position: $0.offset + 1) }
        residue += launchConditionGaps.map(\.line)
        residue.append(Self.scopeLine)
        var lines = notes
        if let turned = report.deviceTurns, !turned.isEmpty {
            lines += (lines.isEmpty ? [] : [""]) + ["⚠ " + DeviceAlignment.note(screens: turned)]
        }
        if !lines.isEmpty {
            residue += [""] + lines
        }
        return Answer(header: header, verdict: verdict, residue: residue)
    }

    /// The header: the same identities a walk's names — build, walkbook, runner, device — and what kind of run it was.
    private var header: String {
        [
            "walk: '\(report.walkName)'",
            "app: \(report.appBundleID)",
            "build: \(ShortHash.of(report.appBuildHash))",
            "walkbook: \(ShortHash.of(report.walkbookHash))",
            report.runnerCommit.map { "runner: \(ShortHash.of($0))\($0.contains("-dirty") ? "-dirty" : "")" },
            "device: \(report.device.name) (\(report.device.osVersion))",
            "dry run: routes only",
        ].compactMap(\.self).joined(separator: "  ")
    }

    /// Every route that did not resolve, named before the count that did.
    ///
    /// **A drift caused by a system sheet the app's snapshot cannot see is its own qualification** (SimWalk#58 item 2), never folded into the ordinary drifted count — mirroring the walk's own verdict (`CaptureBundleSummary`), which counts `.snapshotBlind` apart from a plain unreachable for the same reason: the route is not wrong, the snapshot is blind to it.
    private var verdict: AnswerVerdict {
        var counts = (resolved: 0, drifted: 0, snapshotBlind: 0, unreadable: 0)
        for probe in report.probes {
            switch probe.outcome {
            case .resolved: counts.resolved += 1
            case .drifted(_, _, .snapshotBlind): counts.snapshotBlind += 1
            case .drifted: counts.drifted += 1
            case .unreadable: counts.unreadable += 1
            }
        }
        let localeGapCount = launchConditionGaps.filter { $0.axis == .locale }.count
        let argumentsGapCount = launchConditionGaps.filter { $0.axis == .arguments }.count
        let environmentGapCount = launchConditionGaps.filter { $0.axis == .environment }.count
        let resetGapCount = launchConditionGaps.filter { $0.axis == .resetPermissions }.count
        let locationGapCount = launchConditionGaps.filter { $0.axis == .location }.count
        let orientationGapCount = launchConditionGaps.filter { $0.axis == .orientation }.count
        let stated = [
            AnswerVerdict.qualification(counts.drifted, "route", "drifted from the app"),
            AnswerVerdict.qualification(counts.snapshotBlind, "route", "drifted behind a system sheet the app's snapshot cannot see"),
            AnswerVerdict.qualification(counts.unreadable, "route", "that could not be read to the end"),
            AnswerVerdict.qualification(localeGapCount, "route", "not probed under every locale its screen is walked in"),
            AnswerVerdict.qualification(argumentsGapCount, "route", "not probed under every argument list its screen is walked under"),
            AnswerVerdict.qualification(environmentGapCount, "route", "not probed under every environment its screen is walked under"),
            AnswerVerdict.qualification(resetGapCount, "route", "probed without the permission reset its screen's states name"),
            AnswerVerdict.qualification(locationGapCount, "route", "probed without the location its screen's states name"),
            AnswerVerdict.qualification(orientationGapCount, "route", "probed without the orientation its screen's states name"),
        ].compactMap(\.self) + qualifications
        return AnswerVerdict.reporting(
            qualifications: stated,
            detail: "\(counts.resolved) of \(report.probes.count) route\(report.probes.count == 1 ? "" : "s") resolved · nothing captured"
        )
    }

    /// What a resolved route does and does not claim — stated on every dry run, because "resolved" read as "the walk will capture this screen" is a claim the probe never checked.
    private static var scopeLine: String {
        "each route followed once from a fresh launch, under its screen's first state's launch arguments and the device's own appearance; resolved means every step landed as a walk's would — the screen it reached is not checked against `expect`, which a walk does"
    }

    /// One screen's line, leading with its 1-based place in the walkbook.
    static func probeLine(_ probe: RouteProbe, position: Int) -> String {
        let lead = "  \(position) \(probe.screenID)"
        switch probe.outcome {
        case .resolved:
            return "\(lead) — resolved: \(probe.route.rendered)"
        case let .drifted(index, reason, cause):
            let why = reason ?? "the step did not land, and the runner could say no more"
            let label = cause == .snapshotBlind ? "DRIFTED behind a system sheet the app's snapshot cannot see" : "DRIFTED"
            return "\(lead) — \(label) at \(stop(index, of: probe)) — \(why)\(tail(of: probe))"
        case let .unreadable(index, reason):
            return "\(lead) — UNREADABLE at \(stop(index, of: probe)) — the hierarchy could not be read, so whether it landed is unknown: \(reason)\(tail(of: probe))"
        }
    }

    /// `step 2 of 3, tap 'Heart'` — the step a probe stopped at, with the label it looked for.
    private static func stop(_ index: Int, of probe: RouteProbe) -> String {
        let step = probe.failedStep.map { ", \($0)" } ?? ""
        return "step \(index + 1) of \(probe.route.count)\(step)"
    }

    /// What landed before the step it stopped at, and what was never attempted after it.
    private static func tail(of probe: RouteProbe) -> String {
        let unreached = probe.unreachedSteps.isEmpty ? "" : "; not reached: \(probe.unreachedSteps.rendered)"
        return "; resolved before it: \(probe.resolvedSteps.rendered)\(unreached)"
    }
}

public extension RouteProbeSummary {
    /// A screen whose states name a launch condition the route was probed without: a locale, argument list or environment other than the first state's, or any permission reset or simulated location (SimWalk#36, #44, #62).
    struct LaunchConditionGap: Equatable, Sendable {
        /// The screen.
        public let screenID: String
        /// Which axis differs.
        public let axis: Axis
        /// For `.locale`, the locale the route was probed under (`nil` is the device's own); unused for the other axes, whose first state's launch is named generically in `line`.
        public let probed: String?
        /// For `.locale`, the other locales its states name, in walkbook order, each once (`nil` is the device's own).
        ///
        /// For `.arguments`/`.environment`, the slug of every other state whose value differs from the first state's; for `.resetPermissions`/`.location`/`.orientation`, the slug of every state that names one, the first's included — in walkbook order.
        public let unprobed: [String?]

        public init(screenID: String, axis: Axis, probed: String?, unprobed: [String?]) {
            self.screenID = screenID
            self.axis = axis
            self.probed = probed
            self.unprobed = unprobed
        }

        /// Every screen of `walkbook` with a state whose locale, arguments or environment differs from its first state's, or that resets permissions or sets a location, in walkbook order — one gap per axis.
        public static func all(in walkbook: Walkbook) -> [LaunchConditionGap] {
            walkbook.screens.flatMap { screen -> [LaunchConditionGap] in
                guard let first = screen.states.first else { return [] }
                var gaps: [LaunchConditionGap] = []

                var unprobedLocales: [String?] = []
                for state in screen.states.dropFirst() where state.locale != first.locale && !unprobedLocales.contains(state.locale) {
                    unprobedLocales.append(state.locale)
                }
                if !unprobedLocales.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .locale, probed: first.locale, unprobed: unprobedLocales))
                }

                let argumentSlugs = screen.states.dropFirst().filter { $0.arguments != first.arguments }.map { $0.slug as String? }
                if !argumentSlugs.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .arguments, probed: nil, unprobed: argumentSlugs))
                }

                let environmentSlugs = screen.states.dropFirst().filter { $0.environment != first.environment }.map { $0.slug as String? }
                if !environmentSlugs.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .environment, probed: nil, unprobed: environmentSlugs))
                }

                // Unlike the axes above, these are not compared with the first state's: the dry run applies none of them, the first
                // state's included (SimWalk#62 item 1), so any state that names one is a state the route was probed without.
                let resetSlugs = screen.states.filter { !$0.resourcesToReset.isEmpty }.map { $0.slug as String? }
                if !resetSlugs.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .resetPermissions, probed: nil, unprobed: resetSlugs))
                }

                let locationSlugs = screen.states.filter { $0.location != nil }.map { $0.slug as String? }
                if !locationSlugs.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .location, probed: nil, unprobed: locationSlugs))
                }

                let orientationSlugs = screen.states.filter { $0.orientation != nil }.map { $0.slug as String? }
                if !orientationSlugs.isEmpty {
                    gaps.append(LaunchConditionGap(screenID: screen.id, axis: .orientation, probed: nil, unprobed: orientationSlugs))
                }

                return gaps
            }
        }

        /// The residue line: what the route was probed under, and what a walk will also follow it under.
        var line: String {
            switch axis {
            case .locale:
                return "  ⚠ \(screenID) — probed under \(Self.name(probed)) only; a walk also follows it under \(unprobed.map(Self.name).joined(separator: ", ")), whose labels this run did not check"
            case .arguments, .environment:
                let slugs = unprobed.compactMap(\.self).map { "'\($0)'" }.joined(separator: ", ")
                return "  ⚠ \(screenID) — probed under the first state's \(axis.rawValue) only; a walk also follows state \(slugs) under other \(axis.rawValue), which this run did not check"
            case .orientation:
                // The dry run turns the device only to match a landscape-only app (SimWalk#225), never to a state's orientation, so the route is followed in the device's own.
                let slugs = unprobed.compactMap(\.self).map { "'\($0)'" }.joined(separator: ", ")
                return "  ⚠ \(screenID) — state \(slugs) names \(axis.rawValue), which this run probed without (a dry run turns the device only to match a landscape-only app, and turns it back), so content that depends on orientation may read differently in the walk"
            case .resetPermissions, .location:
                // The dry run must not change the device's permissions or location (the walk's reset and simulated location are the changes), so it probes without them.
                let slugs = unprobed.compactMap(\.self).map { "'\($0)'" }.joined(separator: ", ")
                return "  ⚠ \(screenID) — state \(slugs) names \(axis.rawValue), which this run probed without (a dry run changes neither), so a `systemTap` answering that permission, or content that depends on location, may read differently in the walk"
            }
        }

        private static func name(_ locale: String?) -> String {
            locale.map { "locale \($0)" } ?? "the device's locale"
        }
    }
}

public extension RouteProbeSummary.LaunchConditionGap {
    /// Which launch condition differs from the first state's.
    enum Axis: String, Equatable, Sendable {
        case locale
        case arguments
        case environment
        /// A state's `resetPermissions` — never applied by a dry run (SimWalk#62 item 1).
        case resetPermissions
        /// A state's `location` — never applied by a dry run (SimWalk#62 item 1).
        case location
        /// A state's `orientation` — never applied by a dry run, which does not turn the device (SimWalk#199).
        case orientation
    }
}
