//
// Copyright © Agulhas Labs
//

/// What a walkbook asks for that a physical device cannot give (SimWalk#116).
///
/// A device target has no `simctl`: the host cannot set a locale, a simulated location, a permission reset or a walk-level setup on it. Every one is refused by name before any `devicectl` call, because applying it to nothing and reporting the walk as though it had been honoured is the failure this tool exists to avoid.
public struct DeviceTargetSupport {
    /// One line per offending walk-level `setup` or screen state, in walkbook order; empty when the walkbook can be walked on a device.
    public static func unsupported(in walkbook: Walkbook) -> [String] {
        var lines: [String] = []
        // `increaseContrast` alone has a device form (`devicectl`, ruling 6); privacy grants and the status bar have none.
        if let setup = walkbook.setup, setup.privacy != nil || setup.statusBar != nil {
            lines.append("setup (walk-level) privacy and statusBar need simctl and are not available on a device target; only setup.increaseContrast is")
        }
        for screen in walkbook.screens {
            for state in screen.states {
                lines += unsupported(in: state, label: "screen \(screen.id), state \(state.slug)")
            }
        }
        return lines
    }

    /// One line per key of `state` a device target cannot apply, each led by `label`; empty when it can be applied.
    public static func unsupported(in state: Walkbook.CaptureState, label: String) -> [String] {
        var lines: [String] = []
        if state.locale != nil {
            lines.append("\(label): locale needs simctl and is not available on a device target")
        }
        if state.location != nil {
            lines.append("\(label): location needs simctl and is not available on a device target")
        }
        if state.resetPermissions != nil {
            lines.append("\(label): resetPermissions needs simctl and is untested on a device, so is not available on a device target")
        }
        return lines
    }
}
