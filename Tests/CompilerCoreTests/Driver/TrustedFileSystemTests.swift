#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct TrustedFileSystemTests {
    // MARK: - trustedLoadableFile

    @Test
    func testTrustedLoadableFileReturnsCanonicalPathForTrustedFile() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("libExample.so")
        try writeFile(at: file)

        let resolved = TrustedFileSystem.trustedLoadableFile(file.path)
        #expect(resolved == file.resolvingSymlinksInPath().standardized.path)
    }

    @Test
    func testTrustedLoadableFileRejectsRelativePath() {
        #expect(TrustedFileSystem.trustedLoadableFile("lib/libLLVM.so") == nil)
        #expect(TrustedFileSystem.trustedLoadableFile("libLLVM.so") == nil)
    }

    @Test
    func testTrustedLoadableFileRejectsMissingFile() {
        let missing = "/tmp/does-not-exist-kswiftk-\(UUID().uuidString).so"
        #expect(TrustedFileSystem.trustedLoadableFile(missing) == nil)
    }

    @Test
    func testTrustedLoadableFileRejectsDirectory() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(TrustedFileSystem.trustedLoadableFile(directory.path) == nil)
    }

    @Test
    func testTrustedLoadableFileRejectsWorldWritableFile() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("libExample.so")
        try writeFile(at: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o666))],
            ofItemAtPath: file.path
        )

        #expect(TrustedFileSystem.trustedLoadableFile(file.path) == nil)
    }

    @Test
    func testTrustedLoadableFileRejectsGroupWritableAncestorDirectory() throws {
        let parent = try makeFixtureDirectory(permissions: 0o775)
        defer { try? FileManager.default.removeItem(at: parent) }
        let file = parent.appendingPathComponent("libExample.so")
        try writeFile(at: file)

        #expect(TrustedFileSystem.trustedLoadableFile(file.path) == nil)
    }

    @Test
    func testTrustedLoadableFileRejectsWorldWritableAncestorDirectory() throws {
        // A world-writable ancestor (e.g. a directory another local user can
        // replace) makes the file unsafe even when the file itself looks fine.
        let parent = try makeFixtureDirectory(permissions: 0o777)
        defer { try? FileManager.default.removeItem(at: parent) }
        let file = parent.appendingPathComponent("libExample.so")
        try writeFile(at: file)

        #expect(TrustedFileSystem.trustedLoadableFile(file.path) == nil)
    }

    @Test
    func testTrustedLoadableFileFollowsSymlinkToTrustedTarget() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("libExample.so.1")
        try writeFile(at: target)
        let link = directory.appendingPathComponent("libExample.so")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        let resolved = TrustedFileSystem.trustedLoadableFile(link.path)
        #expect(resolved == target.resolvingSymlinksInPath().standardized.path)
    }

    @Test
    func testTrustedLoadableFileRejectsSymlinkToUntrustedTarget() throws {
        let trustedDirectory = try makeFixtureDirectory()
        let untrustedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: untrustedDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o777))],
            ofItemAtPath: untrustedDirectory.path
        )
        defer {
            try? FileManager.default.removeItem(at: trustedDirectory)
            try? FileManager.default.removeItem(at: untrustedDirectory)
        }
        let target = untrustedDirectory.appendingPathComponent("libExample.so.1")
        try writeFile(at: target)
        let link = trustedDirectory.appendingPathComponent("libExample.so")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        #expect(TrustedFileSystem.trustedLoadableFile(link.path) == nil)
    }

    // MARK: - helpers

    /// Fixtures that must sit under trusted ancestor directories are placed
    /// inside a new directory under the current user's home: its ancestor
    /// chain is owned by the user and not group/other-writable on CI and dev
    /// machines alike, unlike `temporaryDirectory` (world-writable on Linux)
    /// or a checkout that may itself be group-writable.
    private func makeFixtureDirectory(permissions: Int16 = 0o755) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".kswiftk-trustedfs-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: directory.path
        )
        return directory
    }

    private func writeFile(at url: URL) throws {
        try Data().write(to: url)
    }
}
#endif
