import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-038 lambda thunks for useLines
//
// `kk_path_useLines` calls runtimeInvokeCollectionLambda1 which dispatches to
// RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int.
// The first Int argument is closureRaw (0 in tests), the second is the RuntimeListBox
// raw pointer for the sequence of lines.
// These file-scope globals accumulate state since @convention(c) closures cannot capture.

nonisolated(unsafe) private var _useLinesListRaw: Int = 0
nonisolated(unsafe) private var _useLinesInvokedCount: Int = 0

/// Captures the list raw pointer and returns 0 (Unit).
private let useLinesCapture: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, listRaw, outThrown in
    outThrown?.pointee = 0
    _useLinesListRaw = listRaw
    _useLinesInvokedCount += 1
    return 0
}

/// Returns the element count of the received list (unboxed Int directly).
private let useLinesReturnCount: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, listRaw, outThrown in
    outThrown?.pointee = 0
    return kk_list_size(listRaw)
}

/// Always throws an error from within the block.
private let useLinesAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: useLines lambda threw")
    return 0
}

private func fnPtrLambda1(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

/// Tests for STDLIB-IO-PATH-FN-038: Path.useLines
///
/// Covers kk_path_useLines and kk_path_useLines_default — the runtime entries for
/// the kotlin.io.path.useLines extension function.
final class RuntimePathUseLinesTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Helpers

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

    // MARK: - kk_path_useLines_default

    func testUseLinesDefaultInvokesBlockOnceWithAllLines() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _useLinesInvokedCount = 0
        _useLinesListRaw = 0
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesCapture), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_useLinesInvokedCount, 1, "block should be invoked exactly once")
        XCTAssertEqual(kk_list_size(_useLinesListRaw), 3)
    }

    func testUseLinesDefaultEmptyFilePassesEmptyList() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _useLinesInvokedCount = 0
        _useLinesListRaw = 0
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesCapture), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_useLinesInvokedCount, 1)
        XCTAssertEqual(kk_list_size(_useLinesListRaw), 0)
    }

    func testUseLinesDefaultTrailingNewlineDoesNotProduceEmptyLine() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "line1\nline2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _useLinesListRaw = 0
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesCapture), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_list_size(_useLinesListRaw), 2)
    }

    func testUseLinesDefaultNonExistentFileThrows() {
        let pathRaw = runtimeTestPathHandle("/nonexistent/\(UUID().uuidString).txt")
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesCapture), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testUseLinesDefaultBlockReturnValuePropagates() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "a\nb\nc\nd".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        let result = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesReturnCount), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 4)
    }

    func testUseLinesDefaultBlockThrownPropagates() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "line".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrLambda1(useLinesAlwaysThrows), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - kk_path_useLines (with charset)

    func testUseLinesWithDefaultCharsetInvokesBlockOnce() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "one\ntwo\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _useLinesInvokedCount = 0
        _useLinesListRaw = 0
        var thrown = 0
        // charsetRaw == 0 selects UTF-8 (default)
        _ = kk_path_useLines(pathRaw, 0, fnPtrLambda1(useLinesCapture), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_useLinesInvokedCount, 1)
        XCTAssertEqual(kk_list_size(_useLinesListRaw), 3)
    }

    func testUseLinesWithCharsetReturnValuePropagates() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "x\ny\nz".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        let result = kk_path_useLines(pathRaw, 0, fnPtrLambda1(useLinesReturnCount), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 3)
    }
}
