import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-TYPE-004: Runtime tests for kotlin.io.FileTreeWalk
//
// Tests kk_file_walkTopDown, kk_file_walkBottomUp, kk_file_walk_with_direction,
// kk_file_tree_walk_to_list, and kk_file_tree_walk_max_depth.

final class RuntimeFileTreeWalkTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Helpers

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

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func filePathsFromList(_ listRaw: Int) -> [String] {
        // kk_list_get takes a plain integer index, not a boxed one
        let count = kk_unbox_int(kk_list_size(listRaw))
        return (0..<count).map { i in
            let fileRaw = kk_list_get(listRaw, i)
            let pathRaw = kk_file_path(fileRaw)
            return runtimeStringValue(pathRaw)
        }
    }

    // MARK: - Box creation

    func testWalkTopDownCreatesValidHandle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        XCTAssertNotEqual(walkRaw, 0, "kk_file_walkTopDown must return a non-null handle")
    }

    func testWalkBottomUpCreatesValidHandle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkBottomUp(fileRaw)
        XCTAssertNotEqual(walkRaw, 0, "kk_file_walkBottomUp must return a non-null handle")
    }

    // MARK: - toList traversal

    func testToListIncludesRootDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        XCTAssertTrue(
            paths.contains(dir.path),
            "toList() must include the root directory itself; got \(paths)"
        )
    }

    func testToListIncludesNestedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        XCTAssertTrue(
            paths.contains(file.path),
            "toList() must include files inside the root directory; got \(paths)"
        )
    }

    func testToListCountMatchesFileSystemEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        // root + a.txt + sub/ + sub/b.txt = 4
        XCTAssertEqual(paths.count, 4, "toList() must enumerate all entries; got \(paths)")
    }

    // MARK: - TOP_DOWN order

    func testTopDownVisitsDirectoryBeforeContents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "c".write(to: sub.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        let subIndex = try XCTUnwrap(paths.firstIndex(of: sub.path), "sub/ must be in list")
        let fileIndex = try XCTUnwrap(
            paths.firstIndex(of: sub.appendingPathComponent("c.txt").path),
            "c.txt must be in list"
        )
        XCTAssertLessThan(subIndex, fileIndex, "TOP_DOWN: directory must appear before its contents")
    }

    // MARK: - BOTTOM_UP order

    func testBottomUpVisitsContentsBeforeDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "d".write(to: sub.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkBottomUp(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        let subIndex = try XCTUnwrap(paths.firstIndex(of: sub.path), "sub/ must be in list")
        let fileIndex = try XCTUnwrap(
            paths.firstIndex(of: sub.appendingPathComponent("d.txt").path),
            "d.txt must be in list"
        )
        XCTAssertLessThan(fileIndex, subIndex, "BOTTOM_UP: contents must appear before their directory")
    }

    // MARK: - maxDepth

    func testMaxDepthZeroReturnsOnlyRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let limitedRaw = kk_file_tree_walk_max_depth(walkRaw, kk_box_int(0))
        let listRaw = kk_file_tree_walk_to_list(limitedRaw)
        let paths = filePathsFromList(listRaw)

        XCTAssertEqual(paths, [dir.path], "maxDepth(0) must return only the root; got \(paths)")
    }

    func testMaxDepthOneLimitsToDirectChildren() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        let nested = sub.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "e".write(to: dir.appendingPathComponent("e.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let limitedRaw = kk_file_tree_walk_max_depth(walkRaw, kk_box_int(1))
        let listRaw = kk_file_tree_walk_to_list(limitedRaw)
        let paths = filePathsFromList(listRaw)

        XCTAssertTrue(
            paths.contains(sub.path),
            "maxDepth(1) must include direct children; got \(paths)"
        )
        XCTAssertFalse(
            paths.contains(nested.path),
            "maxDepth(1) must exclude grandchildren; got \(paths)"
        )
    }

    func testMaxDepthDoesNotMutateOriginalWalk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        // Create limited copy; original walk should still traverse all depths
        _ = kk_file_tree_walk_max_depth(walkRaw, kk_box_int(0))
        let fullListRaw = kk_file_tree_walk_to_list(walkRaw)
        let fullPaths = filePathsFromList(fullListRaw)

        XCTAssertTrue(
            fullPaths.contains(sub.path),
            "maxDepth() must return a new walk and not mutate the original; got \(fullPaths)"
        )
    }
}
