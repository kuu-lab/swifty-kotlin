@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DiffStdlibCacheIdentityTests {
    @Test
    func linuxMappingsIncludeOnlyFileBackedExecutableCode() {
        let maps = """
        1000-2000 r--p 00000000 00:00 1 /tmp/mapped data
        2000-3000 r-xp 00001000 00:00 1 /tmp/lib with spaces.so
        3000-4000 r-xp 00000000 00:00 0 [vdso]
        4000-5000 r-xp 00000000 00:00 2 /tmp/old.so (deleted)
        """
        #expect(DiffLoadedLibraries.linuxMappedPaths(maps) == [
            "/tmp/lib with spaces.so", "/tmp/old.so (deleted)",
        ])
    }

    @Test
    func identityChangesWithCompilerSourcesDependenciesAndEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let compiler = directory.appendingPathComponent("kswiftc")
        try Data("binary-a".utf8).write(to: compiler)
        let fixedDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: compiler.path)

        func fingerprint(
            sources: String = "source-a",
            dependencies: [(String, String)] = [("llvm", "library-a")],
            environment: [String: String] = ["A": "1", "B": "2"]
        ) throws -> String {
            try #require(DiffStdlibCache.fingerprint(
                executable: compiler.path, sources: sources, dependencies: dependencies,
                environment: environment, operatingSystem: "test-os"
            ))
        }

        let initial = try fingerprint()
        #expect(try fingerprint(environment: ["B": "2", "A": "1"]) == initial)
        #expect(try fingerprint(sources: "source-b") != initial)
        #expect(try fingerprint(dependencies: [("llvm", "library-b")]) != initial)
        #expect(try fingerprint(environment: ["A": "1", "B": "3"]) != initial)
        try Data("binary-b".utf8).write(to: compiler)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: compiler.path)
        #expect(try fingerprint() != initial)
        try FileManager.default.removeItem(at: compiler)
        #expect(DiffStdlibCache.fingerprint(
            executable: compiler.path, sources: "source-a", dependencies: [],
            environment: [:], operatingSystem: "test-os"
        ) == nil)
    }

    @Test
    func llvmIdentityUsesFileContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("libLLVM")
        try Data("llvm-a".utf8).write(to: library)
        let fixedDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: library.path)
        func identity() throws -> String {
            let value = try #require(DiffStdlibCache.dependencyIdentity(path: library.path))
            return "\(value.0)=\(value.1)"
        }
        let initial = try identity()
        try Data("llvm-b".utf8).write(to: library)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: library.path)
        #expect(try identity() != initial)
        try FileManager.default.removeItem(at: library)
        #expect(DiffStdlibCache.dependencyIdentity(path: library.path) == nil)
    }

    @Test
    func bundledSourceIdentityUsesActualResourceContents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stdlib = root.appendingPathComponent("Stdlib")
        try FileManager.default.createDirectory(at: stdlib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = stdlib.appendingPathComponent("sample.kt")
        try Data("fun a() = 1".utf8).write(to: file)
        let first = try #require(try BundledStdlib.sourceFingerprint(resourcePath: root.path))
        try Data("fun a() = 2".utf8).write(to: file)
        let changed = try #require(try BundledStdlib.sourceFingerprint(resourcePath: root.path))
        #expect(first != changed)
        try FileManager.default.removeItem(at: file)
        #expect(try BundledStdlib.sourceFingerprint(resourcePath: root.path) == nil)
    }

    @Test
    func integritySealRejectsModifiedMissingAddedAndSymlinkedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let object = root.appendingPathComponent("stdlib.o")
        try Data("object-a".utf8).write(to: object)
        try DiffStdlibCache.sealArtifact(at: root.path)
        #expect(DiffStdlibCache.isIntactArtifact(at: root.path))
        try Data("object-b".utf8).write(to: object)
        #expect(!DiffStdlibCache.isIntactArtifact(at: root.path))
        try Data("object-a".utf8).write(to: object)
        #expect(DiffStdlibCache.isIntactArtifact(at: root.path))
        let extra = root.appendingPathComponent("extra")
        try Data("extra".utf8).write(to: extra)
        #expect(!DiffStdlibCache.isIntactArtifact(at: root.path))
        try FileManager.default.removeItem(at: extra)
        try FileManager.default.removeItem(at: object)
        #expect(!DiffStdlibCache.isIntactArtifact(at: root.path))
        try FileManager.default.createSymbolicLink(at: object, withDestinationURL: extra)
        #expect(!DiffStdlibCache.isIntactArtifact(at: root.path))
    }
}
