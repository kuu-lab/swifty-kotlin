import Foundation
@testable import Runtime
import XCTest

final class RuntimePathSetAttributeTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

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

    func testSetAttributeLastModifiedTimeSetsModificationDate() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("hello".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try XCTUnwrap(attrs[.modificationDate] as? Date)
        XCTAssertEqual(modDate.timeIntervalSince1970, 1000.0, accuracy: 1.0)
    }

    func testSetAttributeWithoutViewPrefixSetsModificationDate() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("test".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("lastModifiedTime")
        let valueRaw = makeRuntimeString("2000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try XCTUnwrap(attrs[.modificationDate] as? Date)
        XCTAssertEqual(modDate.timeIntervalSince1970, 2000.0, accuracy: 1.0)
    }

    func testSetAttributeLastAccessTimeSucceedsWithoutThrow() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastAccessTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
    }

    func testSetAttributeCreationTimeSetsCreationDate() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:creationTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let creationDate = try XCTUnwrap(attrs[.creationDate] as? Date)
        XCTAssertEqual(creationDate.timeIntervalSince1970, 1000.0, accuracy: 1.0)
    }

    func testSetAttributeUnsupportedAttributeThrows() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("posix:permissions")
        let valueRaw = makeRuntimeString("rwxr-xr-x")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0, "Expected an UnsupportedOperationException for unsupported attribute")
    }

    func testSetAttributeOnNonExistentFileThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let pathRaw = runtimeTestPathHandle(missingPath)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        _ = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0, "Expected an IOException for a non-existent path")
    }

    func testSetAttributeIgnoresOptionsArgument() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let valueRaw = makeRuntimeString("1000000")
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, valueRaw, 42, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
    }

    func testSetAttributeWithFileTimeBoxAsValue() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let attributeRaw = makeRuntimeString("basic:lastModifiedTime")
        let fileTimeRaw = registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 3_000_000))
        var thrown = 0
        let resultRaw = kk_path_setAttribute(pathRaw, attributeRaw, fileTimeRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = try XCTUnwrap(attrs[.modificationDate] as? Date)
        XCTAssertEqual(modDate.timeIntervalSince1970, 3000.0, accuracy: 1.0)
    }
}
