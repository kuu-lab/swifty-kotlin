#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FileFingerprintTests {
    // MARK: - Init

    @Test
    func testInitStoresProperties() {
        let fp = FileFingerprint(path: "/tmp/a.kt", contentHash: "abc123", mtimeNanos: 999)
        #expect(fp.path == "/tmp/a.kt")
        #expect(fp.contentHash == "abc123")
        #expect(fp.mtimeNanos == 999)
    }

    // MARK: - Compute from file contents

    @Test
    func testComputeFromContentsProducesConsistentHash() {
        let data = Data("fun main() {}".utf8)
        let fp1 = FileFingerprint.compute(for: "/fake/path.kt", contents: data)
        let fp2 = FileFingerprint.compute(for: "/fake/path.kt", contents: data)
        #expect(fp1.contentHash == fp2.contentHash)
        #expect(fp1.path == "/fake/path.kt")
    }

    @Test
    func testComputeFromContentsDifferentContentsDifferentHash() {
        let data1 = Data("fun main() {}".utf8)
        let data2 = Data("fun main() { println() }".utf8)
        let fp1 = FileFingerprint.compute(for: "/a.kt", contents: data1)
        let fp2 = FileFingerprint.compute(for: "/a.kt", contents: data2)
        #expect(fp1.contentHash != fp2.contentHash)
    }

    @Test
    func testComputeFromContentsEmptyData() {
        let data = Data()
        let fp = FileFingerprint.compute(for: "/empty.kt", contents: data)
        // SHA-256 of empty input is a well-known constant
        #expect(fp.contentHash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - Compute from file path

    @Test
    func testComputeFromPathReturnsNilForNonExistentFile() {
        let fp = FileFingerprint.compute(for: "/nonexistent/path/that/does/not/exist.kt")
        #expect(fp == nil)
    }

    @Test
    func testComputeFromPathReturnsValidFingerprintForExistingFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
        try "hello world".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fp = FileFingerprint.compute(for: tempURL.path)
        #expect(fp != nil)
        #expect(fp?.path == tempURL.path)
        #expect(!(try #require(fp?.contentHash.isEmpty)))
        #expect(try #require(fp?.mtimeNanos) > 0)
    }

    // MARK: - contentChanged

    @Test
    func testContentChangedReturnsTrueForDifferentHashes() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "aaa", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "bbb", mtimeNanos: 100)
        #expect(fp1.contentChanged(from: fp2))
    }

    @Test
    func testContentChangedReturnsFalseForSameHash() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "same", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "same", mtimeNanos: 200)
        #expect(!(fp1.contentChanged(from: fp2)))
    }

    // MARK: - Equatable

    @Test
    func testEquatable() {
        let fp1 = FileFingerprint(path: "/a.kt", contentHash: "abc", mtimeNanos: 100)
        let fp2 = FileFingerprint(path: "/a.kt", contentHash: "abc", mtimeNanos: 100)
        let fp3 = FileFingerprint(path: "/a.kt", contentHash: "xyz", mtimeNanos: 100)
        #expect(fp1 == fp2)
        #expect(fp1 != fp3)
    }

    // MARK: - Codable round-trip

    @Test
    func testCodableRoundTrip() throws {
        let fp = FileFingerprint(path: "/test.kt", contentHash: "deadbeef", mtimeNanos: 42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(fp)
        let decoder = JSONDecoder()
        let restored = try decoder.decode(FileFingerprint.self, from: data)
        #expect(fp == restored)
    }

    // MARK: - SHA-256 correctness

    @Test
    func testSHA256KnownVector() {
        // "abc" -> ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
        let data = Data("abc".utf8)
        let fp = FileFingerprint.compute(for: "/test.kt", contents: data)
        #expect(fp.contentHash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
#endif
