import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-TYPE-004: Runtime tests for FileTreeWalk

// Global mutable state required by @convention(c) callbacks (cannot capture).
private nonisolated(unsafe) var treeWalkOnLeaveCount: Int = 0
private nonisolated(unsafe) var treeWalkOnEnterCount: Int = 0
private nonisolated(unsafe) var treeWalkVisitedPaths: [String] = []

// Lambda: (File) -> Boolean  — always returns true (allow descent)
private let alwaysEnterTrue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    treeWalkOnEnterCount += 1
    return kk_box_bool(1)
}

// Lambda: (File) -> Boolean  — always returns false (prune all directories)
private let alwaysEnterFalse: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    treeWalkOnEnterCount += 1
    return kk_box_bool(0)
}

// Lambda: (File) -> Unit  — counts onLeave invocations
private let countOnLeave: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    treeWalkOnLeaveCount += 1
    return 0
}

// Lambda: (File) -> Unit  — records the path of each visited file
private let recordFilePath: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, fileRaw, outThrown in
    outThrown?.pointee = 0
    let pathRaw = kk_file_path(fileRaw)
    let path = rtwExtractString(pathRaw)
    treeWalkVisitedPaths.append(path)
    return 0
}

// MARK: - Helpers

private func rtwStringRaw(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
        }
    }
}

private func rtwFileHandle(_ path: String) -> Int {
    kk_file_new(rtwStringRaw(path))
}

private func rtwExtractString(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

// Materialises a FileTreeWalk handle into a sorted array of path strings.
private func treeWalkPaths(_ walkRaw: Int) -> [String] {
    var thrown = 0
    let listRaw = kk_file_tree_walk_toList(walkRaw, &thrown)
    guard thrown == 0 else { return [] }
    let size = kk_list_size(listRaw)
    return (0 ..< size).map { i in
        rtwExtractString(kk_file_path(kk_list_get(listRaw, i)))
    }
}

// MARK: - Test class

final class RuntimeFileTreeWalkTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Basic traversal

    func testTopDownReturnsRootFirst() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_walkTopDown(rtwFileHandle(root))
        let paths = treeWalkPaths(walkRaw)

        // TOP_DOWN: root must be the first element.
        XCTAssertFalse(paths.isEmpty)
        XCTAssertEqual(paths.first, root)
    }

    func testTopDownIncludesAllNodes() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_walkTopDown(rtwFileHandle(root))
        let paths = treeWalkPaths(walkRaw)

        // root + file1.txt + subdir + subdir/file2.txt = 4
        XCTAssertEqual(paths.count, 4)
    }

    func testBottomUpRootIsLast() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_walkBottomUp(rtwFileHandle(root))
        let paths = treeWalkPaths(walkRaw)

        // BOTTOM_UP: root must be the last element.
        XCTAssertFalse(paths.isEmpty)
        XCTAssertEqual(paths.last, root)
    }

    func testBottomUpContainsSameNodesAsTopDown() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let topDown = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(root)))
        let bottomUp = treeWalkPaths(kk_file_walkBottomUp(rtwFileHandle(root)))

        XCTAssertEqual(Set(topDown), Set(bottomUp))
    }

    // MARK: - Empty directory

    func testEmptyDirectoryReturnsOnlyRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let walkRaw = kk_file_walkTopDown(rtwFileHandle(dir.path))
        let paths = treeWalkPaths(walkRaw)

        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first, dir.path)
    }

    // MARK: - Single file

    func testSingleFileYieldsJustItself() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let walkRaw = kk_file_walkTopDown(rtwFileHandle(file.path))
        let paths = treeWalkPaths(walkRaw)

        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first, file.path)
    }

    // MARK: - maxDepth

    func testMaxDepth0YieldsOnlyRoot() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_tree_walk_maxDepth(
            kk_file_walkTopDown(rtwFileHandle(root)),
            kk_box_int(0)
        )
        let paths = treeWalkPaths(walkRaw)

        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first, root)
    }

    func testMaxDepth1StopsAtFirstLevel() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_tree_walk_maxDepth(
            kk_file_walkTopDown(rtwFileHandle(root)),
            kk_box_int(1)
        )
        let paths = treeWalkPaths(walkRaw)

        // root (depth=0), file1.txt (depth=1), subdir (depth=1) = 3
        // subdir/file2.txt (depth=2) must NOT appear.
        XCTAssertEqual(paths.count, 3)
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("file2.txt") }))
    }

    // MARK: - onEnter

    func testOnEnterIsCalledForDirectories() throws {
        treeWalkOnEnterCount = 0
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let fnPtr = unsafeBitCast(alwaysEnterTrue, to: Int.self)
        let walkRaw = kk_file_tree_walk_onEnter(
            kk_file_walkTopDown(rtwFileHandle(root)),
            fnPtr,
            0
        )
        _ = treeWalkPaths(walkRaw)

        // onEnter is called for root and subdir = 2 directories.
        XCTAssertEqual(treeWalkOnEnterCount, 2)
    }

    func testOnEnterFalseSkipsSubtree() throws {
        treeWalkOnEnterCount = 0
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let fnPtr = unsafeBitCast(alwaysEnterFalse, to: Int.self)
        let walkRaw = kk_file_tree_walk_onEnter(
            kk_file_walkTopDown(rtwFileHandle(root)),
            fnPtr,
            0
        )
        let paths = treeWalkPaths(walkRaw)

        // onEnter returns false for all dirs → only the directory nodes themselves
        // are yielded (TOP_DOWN adds dir before deciding to descend), but no children.
        XCTAssertTrue(paths.contains(root))
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("file1.txt") }))
        XCTAssertFalse(paths.contains(where: { $0.hasSuffix("file2.txt") }))
    }

    // MARK: - onLeave

    func testOnLeaveCalledForEachDirectory() throws {
        treeWalkOnLeaveCount = 0
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let fnPtr = unsafeBitCast(countOnLeave, to: Int.self)
        let walkRaw = kk_file_tree_walk_onLeave(
            kk_file_walkTopDown(rtwFileHandle(root)),
            fnPtr,
            0
        )
        _ = treeWalkPaths(walkRaw)

        // onLeave is called after exiting each directory: root and subdir = 2.
        XCTAssertEqual(treeWalkOnLeaveCount, 2)
    }

    // MARK: - forEach

    func testForEachVisitsAllNodes() throws {
        treeWalkVisitedPaths = []
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let fnPtr = unsafeBitCast(recordFilePath, to: Int.self)
        var thrown = 0
        _ = kk_file_tree_walk_forEach(
            kk_file_walkTopDown(rtwFileHandle(root)),
            fnPtr,
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(treeWalkVisitedPaths.count, 4)
        XCTAssertTrue(treeWalkVisitedPaths.contains(root))
    }

    // MARK: - Helpers

    /// Creates: <tmpdir>/root/file1.txt, <tmpdir>/root/subdir/file2.txt
    private func makeTempDirTree() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let subdir = root.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "content1".write(to: root.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "content2".write(to: subdir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
        return root.path
    }
}
