import Foundation
@testable import Runtime
import Testing

// MARK: - Runtime tests for kk_file_walk (java.io.File.walk)
//
// `kk_file_walk` materialises the file tree rooted at the receiver eagerly as a
// `List<File>` in TOP_DOWN (preorder) order, with directory entries sorted by
// name so the traversal is deterministic.

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

/// Materialises the `List<File>` returned by `kk_file_walk` into path strings.
private func walkPaths(_ listRaw: Int) -> [String] {
    let size = kk_unbox_int(kk_list_size(listRaw))
    return (0 ..< size).map { i in
        rtwExtractString(kk_file_path(kk_list_get(listRaw, i)))
    }
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeFileWalkTests {
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

    @Test func walkReturnsRootFirst() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = walkPaths(kk_file_walk(rtwFileHandle(root)))

        #expect(paths.first == root, "kk_file_walk must be TOP_DOWN (root first)")
    }

    @Test func walkIncludesAllNodes() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = walkPaths(kk_file_walk(rtwFileHandle(root)))

        // root + file1.txt + subdir + subdir/file2.txt = 4
        #expect(paths.count == 4)
        #expect(paths.contains(where: { $0.hasSuffix("/file1.txt") }))
        #expect(paths.contains(where: { $0.hasSuffix("/subdir/file2.txt") }))
    }

    @Test func walkVisitsDirectoryBeforeItsContents() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let paths = walkPaths(kk_file_walk(rtwFileHandle(root)))
        let subdirIndex = try #require(paths.firstIndex(where: { $0.hasSuffix("/subdir") }))
        let childIndex = try #require(paths.firstIndex(where: { $0.hasSuffix("/subdir/file2.txt") }))

        #expect(subdirIndex < childIndex)
    }

    @Test func walkSortsDirectoryEntriesByName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["c.txt", "a.txt", "b.txt"] {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let names = walkPaths(kk_file_walk(rtwFileHandle(root.path)))
            .dropFirst()
            .map { ($0 as NSString).lastPathComponent }

        #expect(Array(names) == ["a.txt", "b.txt", "c.txt"])
    }

    @Test func walkOnEmptyDirectoryReturnsOnlyRoot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let paths = walkPaths(kk_file_walk(rtwFileHandle(dir.path)))

        #expect(paths == [dir.path])
    }

    @Test func walkOnRegularFileYieldsJustItself() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let paths = walkPaths(kk_file_walk(rtwFileHandle(file.path)))

        #expect(paths == [file.path])
    }
}
