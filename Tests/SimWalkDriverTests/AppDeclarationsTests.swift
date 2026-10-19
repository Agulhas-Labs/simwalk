//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// An installed app's declarations are read from its Info.plist and the entitlements section of its executable, and an app that cannot be read says which file and why.
struct AppDeclarationsTests {
    private static let entitlements = ["com.apple.developer.healthkit", "aps-environment", "get-task-allow"]

    /// A thin image carrying the section gives its keys, and the Info.plist gives its keys and background modes.
    @Test
    func thinImageGivesEntitlementsAndInfoPlistDeclarations() throws {
        let app = try Fixture(executable: Self.thin(entitlements: Self.entitlements))

        let found = try app.declarations()

        #expect(found.entitlements == Set(Self.entitlements))
        #expect(found.infoPlistKeys == ["CFBundleExecutable", "UIBackgroundModes", "NSHealthShareUsageDescription"])
        #expect(found.backgroundModes == ["remote-notification", "fetch"])
        #expect(found.storeKitConfiguration == false)
    }

    /// A fat image is read at its arm64 slice, offsets relative to the slice, though an earlier slice has no section.
    @Test
    func fatImageIsReadAtItsArm64Slice() throws {
        let other = Self.thin(entitlements: nil, cpu: 0x0100_0007)
        let arm = Self.thin(entitlements: ["com.apple.developer.icloud-services"])
        let app = try Fixture(executable: Self.fat([(0x0100_0007, other), (0x0100_000C, arm)]))

        #expect(try app.declarations().entitlements == ["com.apple.developer.icloud-services"])
    }

    /// With no arm64 slice the first one is read.
    @Test
    func fatImageWithoutArm64IsReadAtItsFirstSlice() throws {
        let first = Self.thin(entitlements: ["aps-environment"], cpu: 0x0100_0007)
        let app = try Fixture(executable: Self.fat([(0x0100_0007, first)]))

        #expect(try app.declarations().entitlements == ["aps-environment"])
    }

    /// An image with no entitlements section declares none; that is not an error.
    @Test
    func imageWithoutTheSectionHasNoEntitlements() throws {
        let app = try Fixture(executable: Self.thin(entitlements: nil))

        #expect(try app.declarations().entitlements.isEmpty)
    }

    /// A truncated image is unreadable, at every length, and never a crash.
    @Test
    func truncatedImageIsUnreadable() throws {
        let image = Self.thin(entitlements: Self.entitlements)
        for length in [0, 2, 20, 40, 100, 150, image.count - 10] {
            let app = try Fixture(executable: image.prefix(length))

            guard case let .failure(failure) = app.read() else {
                Issue.record("a \(length)-byte image read as success")
                continue
            }
            #expect(failure.reason.hasPrefix("\(app.name)/Gizmo: "), "length \(length): \(failure.reason)")
        }
    }

    /// Bytes that are no Mach-O image are named so.
    @Test
    func nonMachOImageIsUnreadable() throws {
        let app = try Fixture(executable: Data(repeating: 0x41, count: 200))

        #expect(app.read() == .failure(UnreadableAppDeclarations(reason: "\(app.name)/Gizmo: not a Mach-O image")))
    }

    /// An app with no Info.plist names it.
    @Test
    func missingInfoPlistIsUnreadable() throws {
        let app = try Fixture(executable: Self.thin(entitlements: nil), infoPlist: false)

        #expect(app.read() == .failure(UnreadableAppDeclarations(reason: "\(app.name)/Info.plist: no such file")))
    }

    /// An app whose Info.plist names an executable that is not there names the executable.
    @Test
    func missingExecutableIsUnreadable() throws {
        let app = try Fixture(executable: nil)

        #expect(app.read() == .failure(UnreadableAppDeclarations(reason: "\(app.name)/Gizmo: no such file")))
    }

    // MARK: - Fixtures

    private static func le32(_ value: UInt32) -> [UInt8] {
        (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }
    }

    private static func le64(_ value: UInt64) -> [UInt8] {
        (0 ..< 8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        le32(value).reversed()
    }

    private static func name(_ text: String) -> [UInt8] {
        Array(text.utf8) + Array(repeating: 0, count: 16 - text.utf8.count)
    }

    /// A thin 64-bit image: an unrelated command, a `__DATA` segment with a decoy section, then `__TEXT` with a decoy section and, when given, the entitlements.
    private static func thin(entitlements keys: [String]?, cpu: UInt32 = 0x0100_000C) -> Data {
        let payload = keys.map { keys -> Data in
            let plist = Dictionary(uniqueKeysWithValues: keys.map { ($0, true as Any) })
            return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
        }
        let decoy = section("__entitlements", segment: "__DATA", offset: 0, size: 0)
        var textSections = [section("__text", segment: "__TEXT", offset: 0, size: 0)]
        let unrelated = le32(0x2) + le32(24) + [UInt8](repeating: 0, count: 16)
        let dataSegment = segment("__DATA", sections: [decoy])
        let textSize = 72 + 80 * (payload == nil ? 1 : 2)
        let bodyStart = 32 + unrelated.count + dataSegment.count + textSize
        if let payload {
            textSections.append(section("__entitlements", segment: "__TEXT", offset: UInt32(bodyStart), size: UInt64(payload.count)))
        }
        let commands = unrelated + dataSegment + segment("__TEXT", sections: textSections)
        let header = le32(0xFEED_FACF) + le32(cpu) + le32(0) + le32(2) + le32(3) + le32(UInt32(commands.count)) + le32(0) + le32(0)
        return Data(header + commands) + (payload ?? Data())
    }

    private static func segment(_ name: String, sections: [[UInt8]]) -> [UInt8] {
        le32(0x19) + le32(UInt32(72 + 80 * sections.count)) + Self.name(name) + [UInt8](repeating: 0, count: 32)
            + le32(0) + le32(0) + le32(UInt32(sections.count)) + le32(0) + Array(sections.joined())
    }

    private static func section(_ name: String, segment: String, offset: UInt32, size: UInt64) -> [UInt8] {
        Self.name(name) + Self.name(segment) + le64(0) + le64(size) + le32(offset) + [UInt8](repeating: 0, count: 28)
    }

    /// A fat image whose slices sit at 4096-byte steps after the header.
    private static func fat(_ slices: [(cpu: UInt32, image: Data)]) -> Data {
        var header = be32(0xCAFE_BABE) + be32(UInt32(slices.count))
        for (index, slice) in slices.enumerated() {
            header += be32(slice.cpu) + be32(0) + be32(UInt32(4096 * (index + 1))) + be32(UInt32(slice.image.count)) + be32(12)
        }
        var image = Data(header)
        for (index, slice) in slices.enumerated() {
            image.append(Data(repeating: 0, count: 4096 * (index + 1) - image.count))
            image.append(slice.image)
        }
        return image
    }
}

extension AppDeclarationsTests {
    private struct Fixture {
        let name = "Gizmo.app"
        let url: URL

        init(executable: Data?, infoPlist: Bool = true) throws {
            let directory = try TemporaryDirectory()
            url = directory.url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if infoPlist {
                let plist: [String: Any] = [
                    "CFBundleExecutable": "Gizmo",
                    "UIBackgroundModes": ["remote-notification", "fetch"],
                    "NSHealthShareUsageDescription": "Gizmo reads steps.",
                    "NSCameraUsageDescription": false,
                ]
                try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
                    .write(to: url.appendingPathComponent("Info.plist"))
            }
            if let executable {
                try executable.write(to: url.appendingPathComponent("Gizmo"))
            }
            kept = directory
        }

        private let kept: TemporaryDirectory

        func read() -> Result<ProjectDeclarations, UnreadableAppDeclarations> {
            AppDeclarations.read(appPath: url.path)
        }

        func declarations() throws -> ProjectDeclarations {
            try read().get()
        }
    }
}
