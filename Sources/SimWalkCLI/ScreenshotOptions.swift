//
// Copyright © Agulhas Labs
//

import ArgumentParser
import SimWalkCore

/// The screenshot options `inspect` and `session read` share (SimWalk#200).
struct ScreenshotOptions: ParsableArguments {
    @Flag(name: .long, help: "Also write a PNG of the app, fitted to point scale, and answer with its path: the colour, shape and emphasis the text cannot say.")
    var screenshot = false

    @Option(name: .long, help: "Pixels per point of the screenshot, 1 (the default), 2 or 3; implies --screenshot.")
    var screenshotScale: Int?

    /// `.unconditional` for the reason `--match` is: a label may begin with a dash.
    @Option(name: .long, parsing: .unconditional, help: "Crop the screenshot to the element with this label plus 8 pt; implies --screenshot. A label that is not one element writes no image.")
    var screenshotOf: String?

    /// What the options ask for, or `nil` for no screenshot; a scale outside 1…3 is a usage error naming it.
    func request() throws -> ScreenshotFit.Request? {
        do {
            return try ScreenshotOption.request(screenshot: screenshot, scale: screenshotScale, of: screenshotOf)
        } catch {
            throw ValidationError("\(error)")
        }
    }

    func validate() throws {
        _ = try request()
    }
}
