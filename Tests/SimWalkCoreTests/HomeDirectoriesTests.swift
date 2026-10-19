//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

#if os(macOS)
/// A harness redirects the whole install with `HOME`, `SIMWALK_HOME` and `SIFT_HOME`; a relative value is no redirect.
struct HomeDirectoriesTests {
    @Test
    func homeMovesTheUserHomeAndTheSimwalkHomeWithIt() {
        let environment = ["HOME": "/x"]

        #expect(HomeDirectories.user(environment: environment).path == "/x")
        #expect(HomeDirectories.simwalk(environment: environment).path == "/x/.simwalk")
        #expect(HomeDirectories.sift(environment: environment).path == "/x/.sift")
    }

    @Test
    func fixedUserHomeBeatsHome() {
        let environment = ["HOME": "/a", "CFFIXED_USER_HOME": "/b"]

        #expect(HomeDirectories.user(environment: environment).path == "/b")
        #expect(HomeDirectories.simwalk(environment: environment).path == "/b/.simwalk")
    }

    @Test
    func homeAnswersWhenFixedUserHomeIsRelativeOrAbsent() {
        #expect(HomeDirectories.user(environment: ["HOME": "/a", "CFFIXED_USER_HOME": "rel"]).path == "/a")
        #expect(HomeDirectories.user(environment: ["CFFIXED_USER_HOME": "/b"]).path == "/b")
    }

    @Test
    func accountHomeIsTheAccountsWhateverTheEnvironmentSays() {
        #expect(HomeDirectories.account().path == FileManager.default.homeDirectoryForCurrentUser.path + "/.simwalk")
    }

    @Test
    func simwalkHomeWinsOverHome() {
        let environment = ["HOME": "/x", "SIMWALK_HOME": "/y"]

        #expect(HomeDirectories.simwalk(environment: environment).path == "/y")
        #expect(HomeDirectories.user(environment: environment).path == "/x")
    }

    @Test
    func aRelativeOrEmptyValueIsIgnored() {
        let environment = ["HOME": "/x", "SIMWALK_HOME": "rel/y", "SIFT_HOME": ""]

        #expect(HomeDirectories.simwalk(environment: environment).path == "/x/.simwalk")
        #expect(HomeDirectories.sift(environment: environment).path == "/x/.sift")
        #expect(HomeDirectories.user(environment: ["HOME": "relative"]).path == Self.accountHome)
    }

    @Test
    func siftHomeMovesTheShimDirectory() {
        let environment = ["HOME": "/x", "SIFT_HOME": "/z"]

        #expect(HomeDirectories.sift(environment: environment).appendingPathComponent("statusline.d").path == "/z/statusline.d")
    }

    @Test
    func noHomeFallsBackToTheAccountHome() {
        #expect(HomeDirectories.user(environment: [:]).path == Self.accountHome)
        #expect(HomeDirectories.simwalk(environment: [:]).path == Self.accountHome + "/.simwalk")
    }

    /// The password database's answer, which `HOME` cannot touch.
    private static var accountHome: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? ""
    }
}
#endif
