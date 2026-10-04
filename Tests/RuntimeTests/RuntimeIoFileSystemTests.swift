import Foundation
@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeIoFileSystemTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func metadataFollowsLinksAndReportsFileByteSize() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data("héllo".utf8).write(to: file)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)
        let metadata = __kk_io_fs_metadata(runtimeMakeStringRaw(link.path))
        #expect(kk_array_get(metadata, 0, nil) == 1)
        #expect(kk_array_get(metadata, 1, nil) == 0)
        #expect(kk_array_get(metadata, 2, nil) == 6)
        let directory = __kk_io_fs_metadata(runtimeMakeStringRaw(root.path))
        #expect(kk_array_get(directory, 0, nil) == 0)
        #expect(kk_array_get(directory, 1, nil) == 1)
        #expect(kk_array_get(directory, 2, nil) == -1)
        #expect(__kk_io_fs_metadata(runtimeMakeStringRaw(file.path + "/child")) == runtimeNullSentinelInt)
        #expect(__kk_io_fs_exists(runtimeMakeStringRaw(link.path)) == 1)
        var thrown = 123
        let resolved = __kk_io_fs_resolve(runtimeMakeStringRaw(link.path), &thrown)
        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: resolved)) == file.resolvingSymlinksInPath().path)
    }

    @Test func deleteIsNonRecursiveAndHonorsMustExist() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("child")
        try Data([1]).write(to: child)
        var thrown = 0
        _ = __kk_io_fs_delete(runtimeMakeStringRaw(root.path), 1, &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
        #expect(FileManager.default.fileExists(atPath: child.path))
        _ = __kk_io_fs_delete(runtimeMakeStringRaw(child.path), 1, &thrown)
        #expect(thrown == 0)
        _ = __kk_io_fs_delete(runtimeMakeStringRaw(child.path), 0, &thrown)
        #expect(thrown == 0)
        _ = __kk_io_fs_delete(runtimeMakeStringRaw(child.path), 1, &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.files.FileNotFoundException")
        _ = __kk_io_fs_delete(runtimeMakeStringRaw(root.path), 1, &thrown)
        #expect(thrown == 0)
    }

    @Test func createDirectoriesRejectsFilesAndMustCreateCollisions() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b")
        var thrown = 0
        _ = __kk_io_fs_create_directories(runtimeMakeStringRaw(nested.path), 0, &thrown)
        #expect(thrown == 0)
        _ = __kk_io_fs_create_directories(runtimeMakeStringRaw(nested.path), 0, &thrown)
        #expect(thrown == 0)
        _ = __kk_io_fs_create_directories(runtimeMakeStringRaw(nested.path), 1, &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        for path in [file.path, file.path + "/child"] {
            _ = __kk_io_fs_create_directories(runtimeMakeStringRaw(path), 0, &thrown)
            #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
        }
    }

    @Test func atomicMoveReplacesDestinationAndReportsMissingSource() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try Data([1, 2, 3]).write(to: source)
        try Data([9]).write(to: destination)
        var thrown = 0
        _ = __kk_io_fs_atomic_move(runtimeMakeStringRaw(source.path), runtimeMakeStringRaw(destination.path), &thrown)
        #expect(thrown == 0)
        #expect(try Data(contentsOf: destination) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        _ = __kk_io_fs_atomic_move(runtimeMakeStringRaw(source.path), runtimeMakeStringRaw(destination.path), &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.files.FileNotFoundException")
        _ = __kk_io_fs_atomic_move(runtimeMakeStringRaw(destination.path), runtimeMakeStringRaw(source.path + "/child"), &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
    }

    @Test func listAndResolveDistinguishMissingPathsFromFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)
        var thrown = 0
        let children = __kk_io_fs_list(runtimeMakeStringRaw(root.path), &thrown)
        #expect(thrown == 0)
        #expect(kk_list_size(children) == 1)
        let child = kk_list_get(children, 0, &thrown)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: child)) == "file")
        _ = __kk_io_fs_list(runtimeMakeStringRaw(file.path), &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.IOException")
        let missing = runtimeMakeStringRaw(root.appendingPathComponent("missing").path)
        #expect(__kk_io_fs_exists(missing) == 0)
        #expect(__kk_io_fs_metadata(missing) == runtimeNullSentinelInt)
        _ = __kk_io_fs_list(missing, &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.files.FileNotFoundException")
        _ = __kk_io_fs_resolve(missing, &thrown)
        #expect(runtimeThrowableBox(from: thrown)?.exceptionFQName == "kotlinx.io.files.FileNotFoundException")
    }
}
