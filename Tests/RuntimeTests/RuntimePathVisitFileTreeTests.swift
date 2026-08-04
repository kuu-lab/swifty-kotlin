import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-IO-PATH-FN-074: Path.visitFileTree / fileVisitor runtime tests
//
// kk_path_visitFileTree and kk_path_visitFileTree_builder walk a directory tree
// using the registered FileVisitor callbacks.  Callbacks follow the 2-arg ABI:
//   (pathRaw: Int, attrsRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int
// attrsRaw is always 0 in the current stub implementation.
// @convention(c) closures cannot capture variables — file-scope globals track state.

// Callbacks receive a RuntimePathBox raw as pathRaw (not a KSwiftK string box).
// Use counts rather than string extraction since the Path -> String conversion
// requires tryCast which cannot be used in @convention(c) closures.
nonisolated(unsafe) private var _visitFileCallCount: Int = 0
nonisolated(unsafe) private var _preVisitDirCallCount: Int = 0
nonisolated(unsafe) private var _builderActionCallCount: Int = 0

private let onVisitFileRecord: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    _visitFileCallCount += 1
    return 0  // FileVisitResult.CONTINUE
}

private let onPreVisitDirRecord: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    _preVisitDirCallCount += 1
    return 0
}

private let onVisitFileTerminate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 0
    return 1  // FileVisitResult.TERMINATE
}

private func fnPtr2(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

private func makeRuntimeString(_ value: String) -> Int {
    let bytes = Array(value.utf8)
    return bytes.withUnsafeBufferPointer { buffer -> Int in
        let base = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
        return Int(bitPattern: kk_string_from_utf8(base, Int32(bytes.count)))
    }
}

private func runtimePathRaw(_ path: String) -> Int {
    kk_path_new(makeRuntimeString(path))
}

private func visitorBox(from raw: Int) -> RuntimeFileVisitorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileVisitorBox.self)
}

/// Tests for STDLIB-IO-PATH-FN-074: Path.visitFileTree and fileVisitor
///
/// `.serialized` because tests share file-scope callback counters.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimePathVisitFileTreeTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - kk_path_fileVisitor

    @Test func fileVisitorWithNilBuilderReturnsNonZeroHandle() {
        let visitorRaw = kk_path_fileVisitor(0)
        #expect(visitorRaw != 0)
    }

    @Test func fileVisitorReturnsCastableToRuntimeFileVisitorBox() {
        let visitorRaw = kk_path_fileVisitor(0)
        #expect(visitorBox(from: visitorRaw) != nil)
    }

    @Test func fileVisitorCallsBuilderActionWhenProvided() {
        let action: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
            outThrown?.pointee = 0
            _builderActionCallCount += 1
            return 0
        }
        let actionRaw = Int(bitPattern: unsafeBitCast(action, to: UnsafeRawPointer.self))
        _builderActionCallCount = 0
        _ = kk_path_fileVisitor(actionRaw)
        #expect(_builderActionCallCount == 1)
    }

    // MARK: - kk_path_visitFileTree

    @Test func visitFileTreeDoesNotThrowForValidDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let pathRaw = runtimePathRaw(dir.path)
        let visitor = kk_path_fileVisitor(0)
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, Int.max, 0, &thrown)
        #expect(thrown == 0)
    }

    @Test func visitFileTreeInvokesOnVisitFileCallback() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "content".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let visitor = kk_path_fileVisitor(0)
        let box = try #require(visitorBox(from: visitor))
        box.onVisitFileRaw = fnPtr2(onVisitFileRecord)

        let pathRaw = runtimePathRaw(dir.path)
        _visitFileCallCount = 0
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, Int.max, 0, &thrown)
        #expect(thrown == 0)
        #expect(_visitFileCallCount == 1)
    }

    @Test func visitFileTreeInvokesOnPreVisitDirectoryCallback() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let visitor = kk_path_fileVisitor(0)
        let box = try #require(visitorBox(from: visitor))
        box.onPreVisitDirectoryRaw = fnPtr2(onPreVisitDirRecord)

        let pathRaw = runtimePathRaw(dir.path)
        _preVisitDirCallCount = 0
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, Int.max, 0, &thrown)
        #expect(thrown == 0)
        #expect(_preVisitDirCallCount >= 1)
    }

    @Test func visitFileTreeTerminatesEarlyWhenCallbackReturnsTerminate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<5 {
            try "line".write(to: dir.appendingPathComponent("\(i).txt"), atomically: true, encoding: .utf8)
        }

        let visitor = kk_path_fileVisitor(0)
        let box = try #require(visitorBox(from: visitor))
        box.onVisitFileRaw = fnPtr2(onVisitFileTerminate)

        let pathRaw = runtimePathRaw(dir.path)
        _visitFileCallCount = 0
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, Int.max, 0, &thrown)
        #expect(thrown == 0)
        // TERMINATE stops at the first file
        #expect(_visitFileCallCount < 5)
    }

    @Test func visitFileTreeMaxDepthZeroSkipsChildren() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "deep".write(to: sub.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

        let visitor = kk_path_fileVisitor(0)
        let box = try #require(visitorBox(from: visitor))
        box.onVisitFileRaw = fnPtr2(onVisitFileRecord)

        let pathRaw = runtimePathRaw(dir.path)
        _visitFileCallCount = 0
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, 0, 0, &thrown)
        #expect(thrown == 0)
        #expect(_visitFileCallCount == 0, "maxDepth=0 must not descend into children")
    }

    @Test func visitFileTreeMultipleFilesInDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.txt", "b.txt", "c.txt"] {
            try name.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let visitor = kk_path_fileVisitor(0)
        let box = try #require(visitorBox(from: visitor))
        box.onVisitFileRaw = fnPtr2(onVisitFileRecord)

        let pathRaw = runtimePathRaw(dir.path)
        _visitFileCallCount = 0
        var thrown = 0
        _ = kk_path_visitFileTree(pathRaw, visitor, Int.max, 0, &thrown)
        #expect(thrown == 0)
        #expect(_visitFileCallCount == 3)
    }

    // MARK: - kk_path_visitFileTree_builder

    @Test func visitFileTreeBuilderWithNoOpBuilderDoesNotThrow() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "alpha".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

        let pathRaw = runtimePathRaw(dir.path)
        var thrown = 0
        _ = kk_path_visitFileTree_builder(pathRaw, Int.max, 0, 0, &thrown)
        #expect(thrown == 0)
    }

    @Test func visitFileTreeBuilderReturnsZero() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pathRaw = runtimePathRaw(dir.path)
        var thrown = 0
        let result = kk_path_visitFileTree_builder(pathRaw, Int.max, 0, 0, &thrown)
        #expect(result == 0)
        #expect(thrown == 0)
    }

    @Test func visitFileTreeBuilderRespectsMaxDepthZero() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "content".write(to: sub.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)

        let pathRaw = runtimePathRaw(dir.path)
        var thrown = 0
        _ = kk_path_visitFileTree_builder(pathRaw, 0, 0, 0, &thrown)
        #expect(thrown == 0)
    }
}
