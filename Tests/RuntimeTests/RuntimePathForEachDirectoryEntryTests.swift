import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-019 lambda thunks for forEachDirectoryEntry
//
// `kk_path_forEachDirectoryEntry` calls kk_function_invoke once per matched
// direct child. The argument is the RuntimePathBox raw pointer for the child
// path. These file-scope globals accumulate state across invocations since
// @convention(c) closures cannot capture variables.

nonisolated(unsafe) private var _forEachDirectoryEntryNames: [String] = []

private let forEachDirectoryEntryRecordName: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { pathRaw, outThrown in
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_path_name(pathRaw)),
          let name = extractString(from: ptr)
    else { return 0 }
    _forEachDirectoryEntryNames.append(name)
    return 0
}

private func fnPtrInt1(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

/// Tests for STDLIB-IO-PATH-FN-019: Path.forEachDirectoryEntry.
///
/// Covers kk_path_forEachDirectoryEntry and kk_path_forEachDirectoryEntry_default,
/// the runtime entries for the kotlin.io.path.forEachDirectoryEntry extension.
final class RuntimePathForEachDirectoryEntryTests: IsolatedRuntimeXCTestCase {
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

    private func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "alpha".write(to: directory.appendingPathComponent("alpha.kt"), atomically: true, encoding: .utf8)
        try "beta".write(to: directory.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        return directory
    }

    func testForEachDirectoryEntryDefaultInvokesActionForEachDirectEntry() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _forEachDirectoryEntryNames = []
        let pathRaw = runtimeTestPathHandle(directory.path)
        let result = kk_path_forEachDirectoryEntry_default(pathRaw, fnPtrInt1(forEachDirectoryEntryRecordName), nil)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(_forEachDirectoryEntryNames.sorted(), ["alpha.kt", "beta.txt", "nested"])
    }

    func testForEachDirectoryEntryFiltersByGlob() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _forEachDirectoryEntryNames = []
        let pathRaw = runtimeTestPathHandle(directory.path)
        let globRaw = makeRuntimeString("*.kt")
        let result = kk_path_forEachDirectoryEntry(pathRaw, globRaw, fnPtrInt1(forEachDirectoryEntryRecordName), nil)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(_forEachDirectoryEntryNames, ["alpha.kt"])
    }

    func testForEachDirectoryEntryMissingDirectoryProducesNoInvocations() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        _forEachDirectoryEntryNames = []
        let pathRaw = runtimeTestPathHandle(missingPath.path)
        let result = kk_path_forEachDirectoryEntry_default(pathRaw, fnPtrInt1(forEachDirectoryEntryRecordName), nil)

        XCTAssertEqual(result, 0)
        XCTAssertTrue(_forEachDirectoryEntryNames.isEmpty)
    }
}
