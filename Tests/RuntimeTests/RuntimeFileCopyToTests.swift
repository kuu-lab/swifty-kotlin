import Foundation
@testable import Runtime
import Testing

/// STDLIB-IO-FN-015: Runtime tests for `kk_file_copyTo`.
///
/// Mirrors the behaviour of `kotlin.io.copyTo` on `java.io.File`:
///   public fun File.copyTo(
///       target: File,
///       overwrite: Boolean = false,
///       bufferSize: Int = DEFAULT_BUFFER_SIZE
///   ): File
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeFileCopyToTests {
    // MARK: - Happy paths

    @Test func copyToFreshTargetDuplicatesContents() throws {
        let sourceURL = try makeTempFile(contents: "hello world")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(8 * 1024), &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == targetRaw)
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "hello world")
    }

    @Test func copyToWithOverwriteReplacesExistingTarget() throws {
        let sourceURL = try makeTempFile(contents: "fresh contents")
        let targetURL = try makeTempFile(contents: "old contents")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(1), kk_box_int(8 * 1024), &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == targetRaw)
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "fresh contents")
    }

    @Test func copyToCreatesMissingParentDirectories() throws {
        let sourceURL = try makeTempFile(contents: "payload")
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetURL = parent.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: parent)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(8 * 1024), &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == targetRaw)
        #expect(FileManager.default.fileExists(atPath: parent.path))
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "payload")
    }

    @Test func copyToWithSmallBufferStillCopiesEntireContents() throws {
        let payload = String(repeating: "abcdefghij", count: 100) // 1,000 bytes
        let sourceURL = try makeTempFile(contents: payload)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        // Buffer size of 16 forces ~63 read/write iterations.
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(16), &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == targetRaw)
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == payload)
    }

    // MARK: - Directory handling

    @Test func copyToOnEmptyDirectoryCreatesTargetDirectory() throws {
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceDir.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(8 * 1024), &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == targetRaw)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: targetDir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    // MARK: - Error paths

    @Test func copyToReportsMissingSource() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        _ = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(8 * 1024), &thrown)

        #expect(thrown != 0)
        #expect(!FileManager.default.fileExists(atPath: targetURL.path))
    }

    @Test func copyToWithoutOverwriteReportsExistingTarget() throws {
        let sourceURL = try makeTempFile(contents: "replacement")
        let targetURL = try makeTempFile(contents: "untouched")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), kk_box_int(8 * 1024), &thrown)

        #expect(thrown != 0)
        #expect(resultRaw == targetRaw)
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "untouched")
    }

    @Test func copyToOverwriteOntoNonEmptyDirectoryReportsConflict() throws {
        let sourceURL = try makeTempFile(contents: "data")
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let childFile = targetDir.appendingPathComponent("child.txt")
        try "child".write(to: childFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        _ = kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(1), kk_box_int(8 * 1024), &thrown)

        #expect(thrown != 0)
        // The directory and its child should remain untouched on conflict.
        #expect(FileManager.default.fileExists(atPath: childFile.path))
    }

    // MARK: - Helpers

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runtimeTestFileHandle(_ path: String) -> Int {
        kk_file_new(runtimeStringRaw(path))
    }

    private func runtimeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }
}
