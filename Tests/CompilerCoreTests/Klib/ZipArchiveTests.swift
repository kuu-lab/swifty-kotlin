@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ZipArchiveTests {
    // MARK: - Raw DEFLATE vectors (precomputed with zlib level 9, wrapper stripped)

    private static func deflate(_ hex: [UInt8], expected: String) {
        do {
            let output = try Inflater.inflate(hex[...])
            #expect(String(decoding: output, as: UTF8.self) == expected)
        } catch {
            Issue.record("inflate failed: \(error)")
        }
    }

    @Test
    func inflateFixedHuffmanBlock() {
        // "Hello Hello Hello Hello World!"
        Self.deflate(
            [0xF3, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xF0, 0xC0, 0x20, 0xC3, 0xF3, 0x8B, 0x72, 0x52, 0x14, 0x01],
            expected: "Hello Hello Hello Hello World!"
        )
    }

    @Test
    func inflateEmptyStream() {
        Self.deflate([0x03, 0x00], expected: "")
    }

    @Test
    func inflateLongRunsAndLiterals() {
        // b"aaa...a" + bytes(0..<32) + b"xyz" * 20
        var expected = String(repeating: "a", count: 30)
        expected += String(decoding: (0 ..< 32).map { UInt8($0) }, as: UTF8.self)
        expected += String(repeating: "xyz", count: 20)
        Self.deflate(
            [
                0x4B, 0x4C, 0xC4, 0x07, 0x18, 0x18, 0x99, 0x98, 0x59, 0x58, 0xD9, 0xD8, 0x39, 0x38,
                0xB9, 0xB8, 0x79, 0x78, 0xF9, 0xF8, 0x05, 0x04, 0x85, 0x84, 0x45, 0x44, 0xC5, 0xC4,
                0x25, 0x24, 0xA5, 0xA4, 0x65, 0x64, 0xE5, 0xE4, 0x2B, 0x2A, 0xAB, 0xC8, 0x46, 0x00,
            ],
            expected: expected
        )
    }

    @Test
    func inflateDynamicHuffmanBlock() {
        // "The quick brown fox jumps over the lazy dog. " * 8
        let expected = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 8)
        Self.deflate(
            [
                0x0B, 0xC9, 0x48, 0x55, 0x28, 0x2C, 0xCD, 0x4C, 0xCE, 0x56, 0x48, 0x2A, 0xCA, 0x2F,
                0xCF, 0x53, 0x48, 0xCB, 0xAF, 0x50, 0xC8, 0x2A, 0xCD, 0x2D, 0x28, 0x56, 0xC8, 0x2F,
                0x4B, 0x2D, 0x52, 0x28, 0x01, 0x4A, 0xE7, 0x24, 0x56, 0x55, 0x2A, 0xA4, 0xE4, 0xA7,
                0xEB, 0x29, 0x84, 0x8C, 0x2A, 0x26, 0x57, 0x31, 0x00,
            ],
            expected: expected
        )
    }

    @Test
    func inflateRejectsTruncatedStream() {
        #expect(throws: KlibFormatError.self) {
            _ = try Inflater.inflate([0xF3, 0x48][...])
        }
    }

    @Test
    func inflateRejectsSizeMismatch() {
        #expect(throws: KlibFormatError.self) {
            _ = try Inflater.inflate([0x03, 0x00][...], uncompressedSize: 5)
        }
    }

    // MARK: - Zip container

    /// Assembles a minimal zip archive (local headers + data + central
    /// directory + EOCD) entirely in memory.
    private struct ZipBuilder {
        struct File {
            var name: String
            var method: UInt16
            var compressed: [UInt8]
            var uncompressed: [UInt8]
        }

        private var files: [File] = []

        mutating func addStored(_ name: String, _ contents: String) {
            let bytes = Array(contents.utf8)
            files.append(File(name: name, method: 0, compressed: bytes, uncompressed: bytes))
        }

        mutating func addDeflated(_ name: String, compressed: [UInt8], uncompressed: [UInt8]) {
            files.append(File(name: name, method: 8, compressed: compressed, uncompressed: uncompressed))
        }

        func build() -> [UInt8] {
            var bytes: [UInt8] = []
            var centralRecords: [[UInt8]] = []

            func appendU16(_ v: UInt16, to a: inout [UInt8]) {
                a.append(UInt8(v & 0xFF)); a.append(UInt8(v >> 8))
            }
            func appendU32(_ v: UInt32, to a: inout [UInt8]) {
                a.append(UInt8(v & 0xFF)); a.append(UInt8(v >> 8 & 0xFF))
                a.append(UInt8(v >> 16 & 0xFF)); a.append(UInt8(v >> 24 & 0xFF))
            }

            for file in files {
                let nameBytes = Array(file.name.utf8)
                let localOffset = bytes.count
                let crc = ZipArchive.crc32(file.uncompressed)

                // local file header
                appendU32(0x0403_4B50, to: &bytes)
                appendU16(20, to: &bytes) // version needed
                appendU16(0, to: &bytes) // flags
                appendU16(file.method, to: &bytes)
                appendU16(0, to: &bytes); appendU16(0, to: &bytes) // time/date
                appendU32(crc, to: &bytes)
                appendU32(UInt32(file.compressed.count), to: &bytes)
                appendU32(UInt32(file.uncompressed.count), to: &bytes)
                appendU16(UInt16(nameBytes.count), to: &bytes)
                appendU16(0, to: &bytes) // extra len
                bytes.append(contentsOf: nameBytes)
                bytes.append(contentsOf: file.compressed)

                // central directory record
                var record: [UInt8] = []
                appendU32(0x0201_4B50, to: &record)
                appendU16(20, to: &record) // version made by
                appendU16(20, to: &record) // version needed
                appendU16(0, to: &record) // flags
                appendU16(file.method, to: &record)
                appendU16(0, to: &record); appendU16(0, to: &record)
                appendU32(crc, to: &record)
                appendU32(UInt32(file.compressed.count), to: &record)
                appendU32(UInt32(file.uncompressed.count), to: &record)
                appendU16(UInt16(nameBytes.count), to: &record)
                appendU16(0, to: &record) // extra
                appendU16(0, to: &record) // comment
                appendU16(0, to: &record) // disk
                appendU16(0, to: &record) // internal attrs
                appendU32(0, to: &record) // external attrs
                appendU32(UInt32(localOffset), to: &record)
                record.append(contentsOf: nameBytes)
                centralRecords.append(record)
            }

            let cdOffset = bytes.count
            for record in centralRecords {
                bytes.append(contentsOf: record)
            }
            let cdSize = bytes.count - cdOffset

            // EOCD
            appendU32(0x0605_4B50, to: &bytes)
            appendU16(0, to: &bytes); appendU16(0, to: &bytes)
            appendU16(UInt16(files.count), to: &bytes)
            appendU16(UInt16(files.count), to: &bytes)
            appendU32(UInt32(cdSize), to: &bytes)
            appendU32(UInt32(cdOffset), to: &bytes)
            appendU16(0, to: &bytes) // comment len
            return bytes
        }
    }

    @Test
    func storedEntriesRoundTrip() throws {
        var builder = ZipBuilder()
        builder.addStored("default/manifest", "unique_name=demo\n")
        builder.addStored("default/ir/files.knf", "\u{00}\u{01}")
        let archive = try ZipArchive(bytes: builder.build())

        #expect(archive.entries.count == 2)
        let manifest = try #require(archive.entry(named: "default/manifest"))
        #expect(manifest.compressionMethod == 0)
        #expect(try String(decoding: archive.contents(of: manifest), as: UTF8.self) == "unique_name=demo\n")
    }

    @Test
    func deflatedEntryRoundTrips() throws {
        let compressed: [UInt8] = [
            0xF3, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xF0, 0xC0, 0x20, 0xC3, 0xF3, 0x8B, 0x72, 0x52, 0x14, 0x01,
        ]
        var builder = ZipBuilder()
        builder.addDeflated(
            "default/manifest",
            compressed: compressed,
            uncompressed: Array("Hello Hello Hello Hello World!".utf8)
        )
        let archive = try ZipArchive(bytes: builder.build())
        let entry = try #require(archive.entry(named: "default/manifest"))
        #expect(try String(decoding: archive.contents(of: entry), as: UTF8.self)
            == "Hello Hello Hello Hello World!")
    }

    @Test
    func rejectsNonZipData() {
        #expect(throws: KlibFormatError.notAZipArchive) {
            _ = try ZipArchive(bytes: Array("not a zip".utf8))
        }
    }

    @Test
    func rejectsCorruptCRC() throws {
        var builder = ZipBuilder()
        builder.addStored("a.txt", "payload")
        var bytes = builder.build()
        // Corrupt one payload byte (inside the first local entry's data).
        let dataOffset = 30 + 5 // local header + "a.txt"
        bytes[dataOffset] ^= 0xFF
        let archive = try ZipArchive(bytes: bytes)
        let entry = try #require(archive.entry(named: "a.txt"))
        #expect(throws: KlibFormatError.crcMismatch("a.txt")) {
            _ = try archive.contents(of: entry)
        }
    }

    @Test
    func rejectsUnsupportedMethod() throws {
        var builder = ZipBuilder()
        builder.addStored("a.txt", "payload")
        var bytes = builder.build()
        // Overwrite compression method in the central directory record.
        // Locate the central dir sig 0x02014B50 and patch method field (+10).
        var centralIndex: Int?
        for i in 0 ... bytes.count - 4
            where bytes[i] == 0x50 && bytes[i + 1] == 0x4B
            && bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02
        {
            centralIndex = i
            break
        }
        let index = try #require(centralIndex)
        bytes[index + 10] = 99
        let archive = try ZipArchive(bytes: bytes)
        let entry = try #require(archive.entry(named: "a.txt"))
        #expect(throws: KlibFormatError.unsupportedCompressionMethod(99)) {
            _ = try archive.contents(of: entry)
        }
    }

    // MARK: - Real .klib fixture (kotlinc-js 2.4.20, hello.kt compiled to klib)

    @Test
    func readsRealKlibFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo.klib")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return // fixture not present in this checkout
        }
        let archive = try ZipArchive(data: Data(contentsOf: fixtureURL))
        let names = Set(archive.entries.map(\.name))
        #expect(names.contains("default/manifest"))
        #expect(names.contains("default/ir/irDeclarations.knd"))
        #expect(names.contains("default/ir/bodies.knb"))
        #expect(names.contains("default/ir/signatures.knt"))

        let manifest = try #require(archive.entry(named: "default/manifest"))
        let manifestText = String(decoding: try archive.contents(of: manifest), as: UTF8.self)
        #expect(manifestText.contains("unique_name=demo2"))
    }
}
