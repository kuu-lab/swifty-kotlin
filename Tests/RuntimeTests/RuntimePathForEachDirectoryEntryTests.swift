import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-019 lambda thunks for forEachDirectoryEntry
//
// `kk_path_forEachDirectoryEntry` calls kk_function_invoke which dispatches to
// KKFunctionEntryPoint1 = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int.
// The argument is the boxed Path raw pointer for the current entry.

nonisolated(unsafe) private var _forEachDirectoryEntryCount: Int = 0

private let forEachDirectoryEntryCounter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    _forEachDirectoryEntryCount += 1
    return 0
}

nonisolated(unsafe) private var _forEachDirectoryEntryNames: [String] = []

private let forEachDirectoryEntryNameCollector: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { arg, outThrown in
    outThrown?.pointee = 0
    if let ptr = UnsafeMutableRawPointer(bitPattern: arg),
       let pathBox = tryCast(ptr, to: RuntimePathBox.self) {
        let name = (pathBox.pathString as NSString).lastPathComponent
        _forEachDirectoryEntryNames.append(name)
    }
    return 0
}

private let forEachDirectoryEntryAlwaysThrows: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: forEachDirectoryEntry lambda threw")
    return 0
}

private func fnPtrInt1(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

/// Tests for STDLIB-IO-PATH-FN-019: Path.forEachDirectoryEntry
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

    func testForEachDirectoryEntryDefaultListsAllDirectChildren() throws {
        let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        try "".write(to: dirURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "".write(to: dirURL.appendingPathComponent("b.kt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dirURL.appendingPathComponent("subdir"), withIntermediateDirectories: true)

        let pathRaw = runtimeTestPathHandle(dirURL.path)
        _forEachDirectoryEntryNames = []
        var thrown = 0
        _ = kk_path_forEachDirectoryEntry_default(pathRaw, fnPtrInt1(forEachDirectoryEntryNameCollector), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachDirectoryEntryNames.sorted(), ["a.txt", "b.kt", "subdir"])
    }

    func testForEachDirectoryEntryWithGlobFiltersChildren() throws {
        let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        try "".write(to: dirURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "".write(to: dirURL.appendingPathComponent("b.kt"), atomically: true, encoding: .utf8)
        try "".write(to: dirURL.appendingPathComponent("c.kt"), atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(dirURL.path)
        let globRaw = makeRuntimeString("*.kt")
        _forEachDirectoryEntryNames = []
        var thrown = 0
        _ = kk_path_forEachDirectoryEntry(pathRaw, globRaw, fnPtrInt1(forEachDirectoryEntryNameCollector), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachDirectoryEntryNames.sorted(), ["b.kt", "c.kt"])
    }

    func testForEachDirectoryEntryNonExistentDirectoryReturnsZero() {
        let pathRaw = runtimeTestPathHandle("/nonexistent/\(UUID().uuidString)")
        _forEachDirectoryEntryCount = 0
        var thrown = 0
        _ = kk_path_forEachDirectoryEntry_default(pathRaw, fnPtrInt1(forEachDirectoryEntryCounter), &thrown)
        
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachDirectoryEntryCount, 0)
    }

    func testForEachDirectoryEntryLambdaThrownPropagates() throws {
        let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        try "".write(to: dirURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(dirURL.path)
        var thrown = 0
        _ = kk_path_forEachDirectoryEntry_default(pathRaw, fnPtrInt1(forEachDirectoryEntryAlwaysThrows), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }
}
