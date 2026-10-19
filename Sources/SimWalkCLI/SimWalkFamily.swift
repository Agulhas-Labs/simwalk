//
// Copyright © Agulhas Labs
//

import Fieldwork

/// The Fieldwork family `simwalk install` installs after its own step; the step skips simwalk itself, so the list is the same in every member.
struct SimWalkFamily {
    static let members = [Family.Member(tool: FieldworkTool(name: "sift")), Family.Member(tool: .simwalk)]
}
