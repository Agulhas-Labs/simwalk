import SimWalkCore
import SimWalkMCP

/// A walk's start and its end: the progress file begun and announced first, the answer's body between, and a run nothing else ended closed once the body is over.
///
/// The begin comes before the target and the device are resolved, so a bounded MCP server has the walk's handle within milliseconds of the call (`Docs/Reference.md`, "Bounded walks").
struct WalkStart {
    let telemetry: WalkTelemetry
    /// The usage-log name the run is begun under.
    let tool: String
    let logPath: String
    /// Hears the claimed progress-file stem and the progress as begun.
    let started: SimWalkMCPServer.WalkStarted?

    /// Begins the run, tells `started`, runs `body` with the telemetry, and ends the run by its answer or its refusal unless something ended it already.
    func run(_ body: (WalkTelemetry) throws -> Answer) throws -> Answer {
        telemetry.begin(tool: tool, logPath: logPath)
        started?(telemetry.writer.url.deletingPathExtension().lastPathComponent, telemetry.writer.current)
        let answer = try WalkTelemetry.recordingUnended(on: telemetry) { try body(telemetry) }
        telemetry.endUnended(by: answer)
        return answer
    }
}
