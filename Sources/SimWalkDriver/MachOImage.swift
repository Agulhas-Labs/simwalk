//
// Copyright © Agulhas Labs
//

import Foundation

/// A Mach-O image held in memory, read far enough to find one section; every read is bounds-checked, so a truncated file is an error and never a crash.
struct MachOImage {
    private static let thin64Magic: UInt32 = 0xFEED_FACF
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fat64Magic: UInt32 = 0xCAFE_BABF
    private static let arm64CPUType: UInt32 = 0x0100_000C
    private static let segment64Command: UInt32 = 0x19

    private let bytes: Data

    init(_ bytes: Data) {
        self.bytes = bytes
    }

    /// The bytes of `name` in `segment`, nil where the image has no such section.
    func section(segment: String, name: String, shownAs file: String) throws -> Data? {
        func truncated() -> UnreadableAppDeclarations {
            UnreadableAppDeclarations(reason: "\(file): truncated Mach-O image")
        }
        guard let magic = try? read(UInt32.self, at: 0, bigEndian: true) else { throw truncated() }
        do {
            switch magic {
            case Self.fatMagic, Self.fat64Magic:
                let start = try archSliceStart(is64: magic == Self.fat64Magic)
                return try sectionOfThinImage(at: start, segment: segment, name: name, file: file)
            default:
                return try sectionOfThinImage(at: 0, segment: segment, name: name, file: file)
            }
        } catch is Truncation {
            throw truncated()
        }
    }

    private func read<T: FixedWidthInteger>(_: T.Type, at offset: Int, bigEndian: Bool = false) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset <= bytes.count - size else { throw Truncation() }
        let start = bytes.startIndex + offset
        var value: T = 0
        for byte in bytes[start ..< start + size] {
            value = (value << 8) | T(byte)
        }
        return bigEndian ? value : value.byteSwapped
    }

    private func range(at offset: Int, length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= bytes.count - length else { throw Truncation() }
        let start = bytes.startIndex + offset
        return bytes[start ..< start + length]
    }

    /// The offset of the arm64 slice of a fat image, else of the first.
    private func archSliceStart(is64: Bool) throws -> Int {
        let count = try Int(read(UInt32.self, at: 4, bigEndian: true))
        guard count > 0 else { throw Truncation() }
        let entrySize = is64 ? 32 : 20
        var first: Int?
        for index in 0 ..< min(count, 64) {
            let entry = 8 + index * entrySize
            let cpu = try read(UInt32.self, at: entry, bigEndian: true)
            let offset = is64 ? try Int(truncatingIfNeeded: read(UInt64.self, at: entry + 8, bigEndian: true)) : try Int(read(UInt32.self, at: entry + 8, bigEndian: true))
            if first == nil {
                first = offset
            }
            if cpu == Self.arm64CPUType {
                return offset
            }
        }
        guard let first else { throw Truncation() }
        return first
    }

    private func sectionOfThinImage(at base: Int, segment: String, name: String, file: String) throws -> Data? {
        guard try read(UInt32.self, at: base) == Self.thin64Magic else {
            throw UnreadableAppDeclarations(reason: "\(file): not a Mach-O image")
        }
        let commandCount = try Int(read(UInt32.self, at: base + 16))
        var command = base + 32
        for _ in 0 ..< commandCount {
            let kind = try read(UInt32.self, at: command)
            let size = try Int(read(UInt32.self, at: command + 4))
            guard size >= 8 else { throw Truncation() }
            if kind == Self.segment64Command, try string(at: command + 8, length: 16) == segment {
                let sectionCount = try Int(read(UInt32.self, at: command + 64))
                var record = command + 72
                for _ in 0 ..< sectionCount {
                    if try string(at: record, length: 16) == name, try string(at: record + 16, length: 16) == segment {
                        let length = try Int(truncatingIfNeeded: read(UInt64.self, at: record + 40))
                        let offset = try Int(read(UInt32.self, at: record + 48))
                        return try range(at: base + offset, length: length)
                    }
                    record += 80
                }
            }
            command += size
        }
        return nil
    }

    private func string(at offset: Int, length: Int) throws -> String {
        let field = try range(at: offset, length: length)
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }
}

extension MachOImage {
    private struct Truncation: Error {}
}
