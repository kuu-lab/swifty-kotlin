import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-039: Path.walk runtime tests

final class RuntimePathWalkTests: XCTestCase {
    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func extractStringRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func makePathRaw(_ value: String) -> Int {
        kk_path_new(makeStringRaw(value))
    }

    private func pathWalkPaths(_ walkRaw: Int) -> [String] {
        let size = kk_unbox_int(kk_list_size(walkRaw))
        return (0 ..< size).map { i in
            extractStringRaw(kk_path_pathString(kk_list_get(walkRaw, i)))
        }
    }

    private func makeTempDirectoryTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-walk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let subDir = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "nested".write(to: subDir.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)
        try "root".write(to: root.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
        return root
    }

    func testPathWalkReturnsValidHandle() throws {
        let root = try makeTempDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let walkRaw = kk_path_walk(makePathRaw(root.path), 0)
        XCTAssertNotEqual(walkRaw, 0, "kk_path_walk must return a non-null handle")
    }

    func testPathWalkIncludesRootDirectory() throws {
        let root = try makeTempDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = pathWalkPaths(kk_path_walk(makePathRaw(root.path), 0))
        XCTAssertEqual(paths.first, root.path, "walk result must include the root directory as first element")
    }

    func testPathWalkEnumeratesSubdirectoriesAndFilesRecursively() throws {
        let root = try makeTempDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = Set(pathWalkPaths(kk_path_walk(makePathRaw(root.path), 0)))
        XCTAssertTrue(paths.contains(root.path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("root.txt").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("sub").path))
        XCTAssertTrue(paths.contains(root.appendingPathComponent("sub/nested.txt").path))
        XCTAssertGreaterThanOrEqual(paths.count, 4)
    }

    func testPathWalkOnEmptyDirectoryReturnsRootOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-walk-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = pathWalkPaths(kk_path_walk(makePathRaw(root.path), 0))
        XCTAssertEqual(paths, [root.path])
    }

    func testPathWalkWithEmptyOptionsList() throws {
        let root = try makeTempDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let emptyOptions = registerRuntimeObject(RuntimeListBox(elements: []))
        let paths = pathWalkPaths(kk_path_walk(makePathRaw(root.path), emptyOptions))
        XCTAssertEqual(paths.first, root.path)
        XCTAssertGreaterThan(paths.count, 1)
    }
}
