import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-IO-TYPE-004: Runtime tests for kotlin.io.FileTreeWalk
//
// Tests kk_file_walkTopDown, kk_file_walkBottomUp, kk_file_walk_with_direction,
// kk_file_tree_walk_to_list, kk_file_tree_walk_max_depth,
// kk_file_tree_walk_filter, kk_file_tree_walk_onEnter, kk_file_tree_walk_onLeave,
// kk_file_tree_walk_onFail, and kk_file_tree_walk_forEach.

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

// MARK: - File-level helpers

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

// Materialises a FileTreeWalk handle into an array of path strings.
private func treeWalkPaths(_ walkRaw: Int) -> [String] {
    let listRaw = kk_file_tree_walk_to_list(walkRaw)
    let size = kk_unbox_int(kk_list_size(listRaw))
    return (0 ..< size).map { i in
        rtwExtractString(kk_file_path(kk_list_get(listRaw, i)))
    }
}

// MARK: - Test suite

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeFileTreeWalkTests {
    // MARK: - Instance helpers

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

    // MARK: - Box creation

    @Test func walkTopDownCreatesValidHandle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        #expect(walkRaw != 0, "kk_file_walkTopDown must return a non-null handle")
    }

    @Test func walkBottomUpCreatesValidHandle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkBottomUp(fileRaw)
        #expect(walkRaw != 0, "kk_file_walkBottomUp must return a non-null handle")
    }

    // MARK: - toList traversal

    @Test func toListIncludesRootDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        #expect(paths.contains(dir.path), "toList() must include the root directory itself; got \(paths)")
    }

    @Test func toListIncludesNestedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        #expect(paths.contains(file.path), "toList() must include files inside the root directory; got \(paths)")
    }

    @Test func toListCountMatchesFileSystemEntries() throws {
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
        #expect(paths.count == 4, "toList() must enumerate all entries; got \(paths)")
    }

    // MARK: - TOP_DOWN order

    @Test func topDownVisitsDirectoryBeforeContents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "c".write(to: sub.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        let subIndex = try #require(paths.firstIndex(of: sub.path), "sub/ must be in list")
        let fileIndex = try #require(
            paths.firstIndex(of: sub.appendingPathComponent("c.txt").path),
            "c.txt must be in list"
        )
        #expect(subIndex < fileIndex, "TOP_DOWN: directory must appear before its contents")
    }

    @Test func topDownReturnsRootFirst() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(root)))

        #expect(!paths.isEmpty)
        #expect(paths.first == root)
    }

    @Test func topDownIncludesAllNodes() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(root)))

        // root + file1.txt + subdir + subdir/file2.txt = 4
        #expect(paths.count == 4)
    }

    // MARK: - BOTTOM_UP order

    @Test func bottomUpVisitsContentsBeforeDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "d".write(to: sub.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkBottomUp(fileRaw)
        let listRaw = kk_file_tree_walk_to_list(walkRaw)
        let paths = filePathsFromList(listRaw)

        let subIndex = try #require(paths.firstIndex(of: sub.path), "sub/ must be in list")
        let fileIndex = try #require(
            paths.firstIndex(of: sub.appendingPathComponent("d.txt").path),
            "d.txt must be in list"
        )
        #expect(fileIndex < subIndex, "BOTTOM_UP: contents must appear before their directory")
    }

    @Test func bottomUpRootIsLast() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = treeWalkPaths(kk_file_walkBottomUp(rtwFileHandle(root)))

        #expect(!paths.isEmpty)
        #expect(paths.last == root)
    }

    @Test func bottomUpContainsSameNodesAsTopDown() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let topDown = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(root)))
        let bottomUp = treeWalkPaths(kk_file_walkBottomUp(rtwFileHandle(root)))

        #expect(Set(topDown) == Set(bottomUp))
    }

    // MARK: - maxDepth

    @Test func maxDepthZeroReturnsOnlyRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileRaw = runtimeTestFileHandle(dir.path)
        let walkRaw = kk_file_walkTopDown(fileRaw)
        let limitedRaw = kk_file_tree_walk_max_depth(walkRaw, kk_box_int(0))
        let listRaw = kk_file_tree_walk_to_list(limitedRaw)
        let paths = filePathsFromList(listRaw)

        #expect(paths == [dir.path], "maxDepth(0) must return only the root; got \(paths)")
    }

    @Test func maxDepthOneLimitsToDirectChildren() throws {
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

        #expect(paths.contains(sub.path), "maxDepth(1) must include direct children; got \(paths)")
        #expect(!paths.contains(nested.path), "maxDepth(1) must exclude grandchildren; got \(paths)")
    }

    @Test func maxDepthDoesNotMutateOriginalWalk() throws {
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

        #expect(
            fullPaths.contains(sub.path),
            "maxDepth() must return a new walk and not mutate the original; got \(fullPaths)"
        )
    }

    @Test func maxDepth0YieldsOnlyRoot() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_tree_walk_max_depth(
            kk_file_walkTopDown(rtwFileHandle(root)),
            kk_box_int(0)
        )
        let paths = treeWalkPaths(walkRaw)

        #expect(paths.count == 1)
        #expect(paths.first == root)
    }

    @Test func maxDepth1StopsAtFirstLevel() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let walkRaw = kk_file_tree_walk_max_depth(
            kk_file_walkTopDown(rtwFileHandle(root)),
            kk_box_int(1)
        )
        let paths = treeWalkPaths(walkRaw)

        // root (depth=0), file1.txt (depth=1), subdir (depth=1) = 3
        // subdir/file2.txt (depth=2) must NOT appear.
        #expect(paths.count == 3)
        #expect(!paths.contains(where: { $0.hasSuffix("file2.txt") }))
    }

    // MARK: - Empty directory

    @Test func emptyDirectoryReturnsOnlyRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let paths = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(dir.path)))

        #expect(paths.count == 1)
        #expect(paths.first == dir.path)
    }

    // MARK: - Single file

    @Test func singleFileYieldsJustItself() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let paths = treeWalkPaths(kk_file_walkTopDown(rtwFileHandle(file.path)))

        #expect(paths.count == 1)
        #expect(paths.first == file.path)
    }

    // MARK: - onEnter

    @Test func onEnterIsCalledForDirectories() throws {
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
        #expect(treeWalkOnEnterCount == 2)
    }

    @Test func onEnterFalseSkipsSubtree() throws {
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

        // onEnter returns false for all dirs → only directory nodes are yielded,
        // no file children.
        #expect(paths.contains(root))
        #expect(!paths.contains(where: { $0.hasSuffix("file1.txt") }))
        #expect(!paths.contains(where: { $0.hasSuffix("file2.txt") }))
    }

    // MARK: - onLeave

    @Test func onLeaveCalledForEachDirectory() throws {
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
        #expect(treeWalkOnLeaveCount == 2)
    }

    // MARK: - STDLIB-IO-PATH-FN-039: kk_file_walk (no-arg, defaults to TOP_DOWN)

    @Test func fileWalkDefaultIsTopDown() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = treeWalkPaths(kk_file_walk(rtwFileHandle(root)))

        #expect(!paths.isEmpty)
        #expect(paths.first == root, "kk_file_walk must default to TOP_DOWN (root first)")
    }

    @Test func fileWalkIncludesAllNodes() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = treeWalkPaths(kk_file_walk(rtwFileHandle(root)))

        // root + file1.txt + subdir + subdir/file2.txt = 4
        #expect(paths.count == 4)
    }

    @Test func fileWalkWithDirectionTopDown() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        // Direction ordinal: 0 = TOP_DOWN
        let walkRaw = kk_file_walk_with_direction(rtwFileHandle(root), kk_box_int(0))
        let paths = treeWalkPaths(walkRaw)

        #expect(paths.first == root, "Direction TOP_DOWN (0) must yield root first")
        #expect(paths.count == 4)
    }

    @Test func fileWalkWithDirectionBottomUp() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        // Direction ordinal: 1 = BOTTOM_UP
        let walkRaw = kk_file_walk_with_direction(rtwFileHandle(root), kk_box_int(1))
        let paths = treeWalkPaths(walkRaw)

        #expect(paths.last == root, "Direction BOTTOM_UP (1) must yield root last")
        #expect(paths.count == 4)
    }

    // MARK: - forEach

    @Test func forEachVisitsAllNodes() throws {
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

        #expect(thrown == 0)
        #expect(treeWalkVisitedPaths.count == 4)
        #expect(treeWalkVisitedPaths.contains(root))
    }
}
