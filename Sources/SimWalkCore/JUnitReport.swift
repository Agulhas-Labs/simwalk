//
// Copyright © Agulhas Labs
//

import Foundation

/// A command's answer as JUnit XML, for a CI test reporter that reads results rather than a verdict line (`--junit <file>`).
///
/// **The failures are the text answer's tallies, not a second opinion.** Each builder (`JUnitWalkCases`, `JUnitDiffCases`, `JUnitAuditCases`, `JUnitOracleCases`) walks the same result the command's summary counts, so a count that moved in one would move in the other. A run with nothing wrong still writes its passing cases, because a CI reporter treats a file with no cases as missing results.
///
/// **Deterministic:** no `time` or `timestamp` attribute, and the cases in the answer's own order, so the same inputs write the same bytes.
public struct JUnitReport: Equatable, Sendable {
    /// The command the report is of, as the suites are named: `walk`, `bundle diff`.
    public let command: String
    public let cases: [JUnitCase]

    public init(command: String, cases: [JUnitCase]) {
        self.command = command
        self.cases = cases
    }

    /// The report of a command that refused: one `<error>` case carrying the refusal line, so a CI report shows why there is nothing else.
    public static func refusal(command: String, reason: String) -> JUnitReport {
        JUnitReport(command: command, cases: [JUnitCase(classname: "simwalk \(command)", name: "refused", result: .errored(AnswerVerdict.refused(reason).line))])
    }

    /// This report with a failing `simwalk` / `verdict` case carrying the verdict line, when the verdict is qualified and no case fails or errors: an exit-2 run never writes an all-green file.
    public func holding(_ verdict: AnswerVerdict) -> JUnitReport {
        guard case .qualified = verdict, failures + errors == 0 else { return self }
        return JUnitReport(command: command, cases: cases + [JUnitCase(classname: "simwalk", name: "verdict", result: .failed(verdict.line))])
    }

    /// The cases with every repeated name within a classname made unique and deterministic.
    ///
    /// The second is ` #2`, the third ` #3`, in case order, because a CI reporter merges cases whose classname and name are equal.
    public var uniquelyNamed: [JUnitCase] {
        var used = Set<String>()
        var repeats: [String: Int] = [:]
        return cases.map { testCase in
            let key = testCase.classname + "\u{0}" + testCase.name
            guard used.contains(key) else {
                used.insert(key)
                return testCase
            }
            var number = repeats[key, default: 1]
            var candidate: String
            repeat {
                number += 1
                candidate = "\(testCase.name) #\(number)"
            } while used.contains(testCase.classname + "\u{0}" + candidate)
            repeats[key] = number
            used.insert(testCase.classname + "\u{0}" + candidate)
            return JUnitCase(classname: testCase.classname, name: candidate, result: testCase.result)
        }
    }

    public var failures: Int {
        count {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
    }

    public var errors: Int {
        count {
            if case .errored = $0 {
                true
            } else {
                false
            }
        }
    }

    public var skipped: Int {
        count {
            if case .skipped = $0 {
                true
            } else {
                false
            }
        }
    }

    /// The XML document.
    public func render() -> String {
        let name = Self.attribute("simwalk \(command)")
        let totals = "tests=\"\(cases.count)\" failures=\"\(failures)\" errors=\"\(errors)\" skipped=\"\(skipped)\""
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<testsuites name=\"\(name)\" \(totals)>", "  <testsuite name=\"\(name)\" \(totals)>"]
        for testCase in uniquelyNamed {
            let open = "    <testcase classname=\"\(Self.attribute(testCase.classname))\" name=\"\(Self.attribute(testCase.name))\""
            switch testCase.result {
            case .passed:
                lines.append(open + "/>")
            case let .failed(message):
                lines += [open + ">", Self.child("failure", message), "    </testcase>"]
            case let .errored(message):
                lines += [open + ">", Self.child("error", message), "    </testcase>"]
            case let .skipped(message):
                lines += [open + ">", Self.child("skipped", message), "    </testcase>"]
            }
        }
        lines += ["  </testsuite>", "</testsuites>", ""]
        return lines.joined(separator: "\n")
    }

    /// The document as the bytes a file holds.
    public func data() -> Data {
        Data(render().utf8)
    }

    private func count(_ matching: (JUnitCase.Result) -> Bool) -> Int {
        cases.filter { matching($0.result) }.count
    }

    private static func child(_ element: String, _ message: String) -> String {
        "      <\(element) message=\"\(attribute(message))\">\(text(message))</\(element)>"
    }

    /// `& < > " '` escaped, and the characters an attribute value would normalise away (tab, line breaks) written as references; control characters XML 1.0 forbids are dropped.
    static func attribute(_ value: String) -> String {
        escape(value) { scalar in
            switch scalar {
            case "\n": "&#10;"
            case "\r": "&#13;"
            case "\t": "&#9;"
            default: nil
            }
        }
    }

    /// `& < > " '` escaped, line breaks kept.
    static func text(_ value: String) -> String {
        escape(value) { _ in nil }
    }

    private static func escape(_ value: String, extra: (Unicode.Scalar) -> String?) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            default:
                if let replacement = extra(scalar) {
                    escaped += replacement
                } else if scalar.value < 0x20, scalar != "\n", scalar != "\r", scalar != "\t" {
                    continue
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}
