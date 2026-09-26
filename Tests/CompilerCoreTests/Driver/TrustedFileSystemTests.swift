#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
        // The fixture's group must be non-administrative for the rejection to
        // hold; the primary group normally is not (e.g. `staff`, `ubuntu`),
        // but chgrp defensively in case it is.
        guard let groupID = nonAdministrativeGroupIDForCurrentUser() else { return }
        try FileManager.default.setAttributes(
            [.groupOwnerAccountID: NSNumber(value: groupID)],
            ofItemAtPath: parent.path
        )
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
    func testTrustedLoadableFileAcceptsAdministrativeGroupWritableAncestor() throws {
        // Standard Homebrew layout: prefix subdirectories such as
        // /opt/homebrew/Cellar are drwxrwxr-x owned by the installing user and
        // group `admin`. Skipped when the current user belongs to no
        // administrative group to chgrp the fixture into.
        guard let groupID = administrativeGroupIDForCurrentUser() else { return }
        let parent = try makeFixtureDirectory(permissions: 0o775)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.setAttributes(
            [.groupOwnerAccountID: NSNumber(value: groupID)],
            ofItemAtPath: parent.path
        )
        let file = parent.appendingPathComponent("libExample.so")
        try writeFile(at: file)

        #expect(TrustedFileSystem.trustedLoadableFile(file.path) != nil)
    }

    @Test
    func testTrustedLoadableFileAcceptsAdministrativeGroupWritableFile() throws {
        // Homebrew keg files may likewise be group-writable to `admin`.
        guard let groupID = administrativeGroupIDForCurrentUser() else { return }
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("libExample.so")
        try writeFile(at: file)
        try FileManager.default.setAttributes(
            [.groupOwnerAccountID: NSNumber(value: groupID),
             .posixPermissions: NSNumber(value: Int16(0o664))],
            ofItemAtPath: file.path
        )

        #expect(TrustedFileSystem.trustedLoadableFile(file.path) != nil)
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

    // MARK: - inspectLoadableFile

    @Test
    func testInspectLoadableFileReportsMissingFile() {
        let missing = "/tmp/does-not-exist-kswiftk-\(UUID().uuidString).so"
        #expect(
            TrustedFileSystem.inspectLoadableFile(missing)
                == .rejected(component: missing, reason: .missing)
        )
    }

    @Test
    func testInspectLoadableFileReportsRelativePath() {
        #expect(
            TrustedFileSystem.inspectLoadableFile("libLLVM.so")
                == .rejected(component: "libLLVM.so", reason: .notAbsolutePath)
        )
    }

    @Test
    func testInspectLoadableFileReportsDirectory() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(
            TrustedFileSystem.inspectLoadableFile(directory.path)
                == .rejected(component: directory.path, reason: .notRegularFile)
        )
    }

    @Test
    func testInspectLoadableFileNamesUntrustedAncestorDirectory() throws {
        let parent = try makeFixtureDirectory(permissions: 0o775)
        defer { try? FileManager.default.removeItem(at: parent) }
        guard let groupID = nonAdministrativeGroupIDForCurrentUser() else { return }
        try FileManager.default.setAttributes(
            [.groupOwnerAccountID: NSNumber(value: groupID)],
            ofItemAtPath: parent.path
        )
        let file = parent.appendingPathComponent("libExample.so")
        try writeFile(at: file)

        guard case .rejected(let component, let reason) = TrustedFileSystem.inspectLoadableFile(file.path) else {
            Issue.record("expected the group-writable ancestor to be rejected")
            return
        }
        #expect(reason == .unsafeOwnershipOrPermissions)
        #expect(component == parent.resolvingSymlinksInPath().standardized.path)
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

    /// The gid of an administrative group (`admin`, `wheel`, `root`, `sudo`)
    /// the current user belongs to, or nil when the user belongs to none —
    /// e.g. a minimal container account.
    private func administrativeGroupIDForCurrentUser() -> gid_t? {
        groupIDsForCurrentUser().first {
            isAdministrativeGroupID($0)
        }
    }

    /// The gid of a non-administrative group the current user belongs to —
    /// almost always the primary group.
    private func nonAdministrativeGroupIDForCurrentUser() -> gid_t? {
        groupIDsForCurrentUser().first {
            !isAdministrativeGroupID($0)
        }
    }

    private func isAdministrativeGroupID(_ groupID: gid_t) -> Bool {
        guard let group = getgrgid(groupID), let name = group.pointee.gr_name else {
            return false
        }
        return TrustedFileSystem.administrativeGroupNames.contains(String(cString: name))
    }

    private func groupIDsForCurrentUser() -> [gid_t] {
        let count = getgroups(0, nil)
        guard count > 0 else {
            return [getegid()]
        }
        var groups = [gid_t](repeating: 0, count: Int(count))
        guard getgroups(count, &groups) > 0 else {
            return [getegid()]
        }
        return groups + [getegid()]
    }
}
#endif
