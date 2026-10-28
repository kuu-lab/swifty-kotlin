#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct IncrementalEnvironmentFingerprintTests {

    private let tempDir = FileManager.default.temporaryDirectory.path
        + "/kswiftk-envfp-\(UUID().uuidString)"

    private func makeOptions(
        searchPaths: [String] = [],
        libraryPaths: [String] = [],
        linkLibraries: [String] = []
    ) -> CompilerOptions {
        CompilerOptions(
            moduleName: "T", inputs: [tempDir + "/main.kt"],
            outputPath: tempDir + "/out", emit: .kirDump,
            searchPaths: searchPaths, libraryPaths: libraryPaths,
            linkLibraries: linkLibraries,
            target: defaultTargetTriple(),
            includeStdlib: false
        )
    }

    // MARK: - file signature

    @Test
    func testSignatureNilForMissingFile() {
        #expect(IncrementalEnvironmentFingerprint.signature(of: tempDir + "/missing") == nil)
    }

    @Test
    func testSignatureChangesWithFileContents() throws {
        let path = tempDir + "/libthing.a"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try Data("v1".utf8).write(to: URL(fileURLWithPath: path))
        let first = try #require(IncrementalEnvironmentFingerprint.signature(of: path))
        // Size is part of the signature, so a rewrite changes it.
        try Data("v1-v1".utf8).write(to: URL(fileURLWithPath: path))
        let second = try #require(IncrementalEnvironmentFingerprint.signature(of: path))
        #expect(first != second)
    }

    // MARK: - environment sensitivity

    @Test
    func testFingerprintDeterministicForSameInputs() {
        let options = makeOptions()
        let environment = ["PATH": "/usr/bin:/bin", "HOME": "/home/test"]
        let first = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: environment
        )
        let second = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: environment
        )
        #expect(first == second)
    }

    @Test
    func testEnvironmentVariableChangeAltersFingerprint() {
        let options = makeOptions()
        let base = ["PATH": "/usr/bin:/bin"]
        let changed = ["PATH": "/usr/bin:/bin", "KSWIFTK_EXTRA": "1"]
        let first = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: base
        )
        let second = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: changed
        )
        #expect(first != second)
        #expect(second.contains { $0 == "env:KSWIFTK_EXTRA=1" })
    }

    // MARK: - link library inputs

    @Test
    func testLinkLibraryResolutionAltersFingerprint() throws {
        let libDir = tempDir + "/libs"
        try FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try Data("lib".utf8).write(to: URL(fileURLWithPath: libDir + "/libfoo.a"))

        let environment = ["PATH": "/usr/bin:/bin"]
        let withoutLib = IncrementalEnvironmentFingerprint.fingerprint(
            for: makeOptions(libraryPaths: [libDir], linkLibraries: ["foo"]),
            environment: environment
        )
        #expect(withoutLib.contains { $0.hasPrefix("lib:foo=") })

        // Replacing the library bytes changes the signature part.
        try Data("lib-lib".utf8).write(to: URL(fileURLWithPath: libDir + "/libfoo.a"))
        let relinked = IncrementalEnvironmentFingerprint.fingerprint(
            for: makeOptions(libraryPaths: [libDir], linkLibraries: ["foo"]),
            environment: environment
        )
        #expect(withoutLib != relinked)
    }

    // MARK: - .kklib inputs

    @Test
    func testKklibManifestAndObjectsAlterFingerprint() throws {
        let searchDir = tempDir + "/search"
        let kklib = searchDir + "/Dep.kklib"
        try FileManager.default.createDirectory(atPath: kklib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        try Data("obj".utf8).write(to: URL(fileURLWithPath: kklib + "/dep.o"))
        try #"{"objects":["dep.o"]}"#.write(
            toFile: kklib + "/manifest.json", atomically: true, encoding: .utf8
        )

        let environment = ["PATH": "/usr/bin:/bin"]
        let options = makeOptions(searchPaths: [searchDir])
        let first = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: environment
        )
        #expect(first.contains { $0.hasPrefix("kklib=") && $0.contains("Dep.kklib") })

        // A manifest rewrite invalidates the fingerprint even when object
        // bytes are untouched.
        try #"{"objects":["dep.o"],"other":1}"#.write(
            toFile: kklib + "/manifest.json", atomically: true, encoding: .utf8
        )
        let second = IncrementalEnvironmentFingerprint.fingerprint(
            for: options, environment: environment
        )
        #expect(first != second)
    }

    @Test
    func testUnrelatedOptionsKeepStaticParts() {
        // The environment/toolchain portion must not depend on source inputs,
        // so two compiles in one process share the same static parts.
        let environment = ["PATH": "/usr/bin:/bin"]
        let first = IncrementalEnvironmentFingerprint.fingerprint(
            for: makeOptions(), environment: environment
        )
        var other = makeOptions()
        other.inputs = [tempDir + "/other.kt"]
        let second = IncrementalEnvironmentFingerprint.fingerprint(
            for: other, environment: environment
        )
        #expect(first == second)
        #expect(first.contains { $0.hasPrefix("executable=") })
    }
}
#endif
