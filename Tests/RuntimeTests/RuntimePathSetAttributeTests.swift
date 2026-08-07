import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePathSetAttributeTests {
    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeRuntimeString(path))
    }

    @Test func setAttributeLastModifiedTimeSetsModificationDate() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("hello".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try #require(attrs[.modificationDate] as? Date)
        #expect(abs(modDate.timeIntervalSince1970 - 1000.0) <= 1.0)
    }

    @Test func setAttributeWithoutViewPrefixSetsModificationDate() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("test".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("lastModifiedTime")
        let valueRaw = makeRuntimeString("2000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try #require(attrs[.modificationDate] as? Date)
        #expect(abs(modDate.timeIntervalSince1970 - 2000.0) <= 1.0)
    }

    @Test func setAttributeLastAccessTimeSucceedsForExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastAccessTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
    }

    @Test func setAttributeLastAccessTimeOnNonExistentFileThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let pathRaw = runtimeTestPathHandle(missingPath)
        let attributeRaw = makeRuntimeString("basic:lastAccessTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown != 0, "Expected an IOException for lastAccessTime on a non-existent path")
    }

    @Test func setAttributeCreationTimeSucceeds() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:creationTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        // On macOS, verify the creation date was actually changed.
        // On Linux, creation time is not settable but the call must still succeed.
        #if canImport(Darwin)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let creationDate = try #require(attrs[.creationDate] as? Date)
        #expect(abs(creationDate.timeIntervalSince1970 - 1000.0) <= 1.0)
        #endif
    }

    @Test func setAttributeCreationTimeOnNonExistentFileThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let pathRaw = runtimeTestPathHandle(missingPath)
        let attributeRaw = makeRuntimeString("basic:creationTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown != 0, "Expected an IOException for creationTime on a non-existent path")
    }

    @Test func setAttributeUnparseableValueThrows() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("not-a-time")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown != 0, "Expected an IllegalArgumentException for unparseable value")
    }

    @Test func setAttributeUnsupportedAttributeThrows() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("posix:permissions")
        let valueRaw = makeRuntimeString("rwxr-xr-x")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown != 0, "Expected an UnsupportedOperationException for unsupported attribute")
    }

    @Test func setAttributeOnNonExistentFileThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let pathRaw = runtimeTestPathHandle(missingPath)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        #expect(thrown != 0, "Expected an IOException for a non-existent path")
    }

    @Test func setAttributeIgnoresOptionsArgument() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 42, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
    }

    @Test func setAttributeWithFileTimeBoxAsValue() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let fileTimeRaw = registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 3_000_000))
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, fileTimeRaw, 0, &thrown)

        #expect(thrown == 0)
        #expect(resultRaw == pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try #require(attrs[.modificationDate] as? Date)
        #expect(abs(modDate.timeIntervalSince1970 - 3000.0) <= 1.0)
    }
}
