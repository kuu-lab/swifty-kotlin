@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// Regression coverage for BUG-051: `discoverScratchRuntimeObjectPaths` only
// searched for objects inside a "Runtime.build"/"Runtime-t.build" products
// directory. A whole-module-optimization (WMO) toolchain instead emits a
// single consolidated "Runtime.o" placed directly in the build directory,
// which the directory-name based search missed, causing
// `KSWIFTK-LINK-0001: Unable to locate packaged runtime object files`.
@Suite(.serialized)
struct CodegenRuntimeObjectDiscoveryTests {
    private func withScratchLayout(
        configuration: RuntimeBuildConfiguration = .debug,
        _ body: (_ buildDirectory: URL, _ scratchRoot: URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let scratchRoot = fileManager.temporaryDirectory
            .appendingPathComponent("bug051-\(UUID().uuidString)", isDirectory: true)
        // Mirror the real scratch layout: <root>/<triple>/<configuration>/Runtime.build
        let buildDirectory = scratchRoot
            .appendingPathComponent("x86_64-unknown-linux-gnu", isDirectory: true)
            .appendingPathComponent(configuration.rawValue, isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
        try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratchRoot) }
        try body(buildDirectory, scratchRoot)
    }

    private func writeObject(_ url: URL) throws {
        try Data("\u{7f}ELF".utf8).write(to: url)
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    @Test
    func testRuntimeBuildConfigurationIsIncludedInArgumentsPathsAndCacheKeys() {
        let target = TargetTriple(
            arch: "arm64",
            vendor: "apple",
            os: "macosx",
            osVersion: nil
        )
        let debugDirectory = CodegenRuntimeSupport.runtimeBuildDirectory(
            target: target,
            configuration: .debug
        )
        let releaseDirectory = CodegenRuntimeSupport.runtimeBuildDirectory(
            target: target,
            configuration: .release
        )
        #expect(debugDirectory != releaseDirectory)
        #expect(debugDirectory.path.contains("/debug/"))
        #expect(releaseDirectory.path.contains("/release/"))

        let debugArguments = CodegenRuntimeSupport.swiftBuildArguments(
            target: target,
            configuration: .debug
        )
        let releaseArguments = CodegenRuntimeSupport.swiftBuildArguments(
            target: target,
            configuration: .release
        )
        #expect(debugArguments.contains { $0 == "debug" })
        #expect(releaseArguments.contains { $0 == "release" })
        #expect(debugArguments != releaseArguments)

        let debugCacheKey = CodegenRuntimeSupport.runtimeBuildCacheKey(
            target: target,
            configuration: .debug
        )
        let releaseCacheKey = CodegenRuntimeSupport.runtimeBuildCacheKey(
            target: target,
            configuration: .release
        )
        #expect(debugCacheKey != releaseCacheKey)
    }

    @Test
    func testRuntimeObjectPathsBuildBothConfigurations() throws {
        let target = TargetTriple.hostDefault()
        for configuration in [RuntimeBuildConfiguration.debug, .release] {
            let paths = try CodegenRuntimeSupport.runtimeObjectPaths(
                target: target,
                configuration: configuration
            )
            #expect(!paths.isEmpty)
            #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0) })
            let cacheKey = CodegenRuntimeSupport.runtimeBuildCacheKey(
                target: target,
                configuration: configuration
            )
            #expect(paths.allSatisfy { $0.contains("/\(cacheKey)/") })
        }
    }

    @Test
    func testDiscoversPerFileObjectsInRuntimeBuildDirectory() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            try writeObject(buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o"))
            try writeObject(buildDirectory.appendingPathComponent("RuntimeBoxing.swift.o"))

            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory,
                scratchRootDirectory: scratchRoot
            )

            #expect(discovered.count == 2)
            #expect(discovered.allSatisfy { $0.hasSuffix(".swift.o") })
        }
    }

    // The core BUG-051 case: WMO emits a single "Runtime.o" directly in the
    // build directory (Runtime.build exists but holds no objects).
    @Test
    func testFallsBackToWholeModuleRuntimeObject() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let debugDirectory = buildDirectory.deletingLastPathComponent()
            let wmoObject = debugDirectory.appendingPathComponent("Runtime.o")
            try writeObject(wmoObject)

            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory,
                scratchRootDirectory: scratchRoot
            )

            #expect(discovered.map(canonicalPath) == [canonicalPath(wmoObject.path)])
        }
    }

    // Per-file objects must win over the WMO fallback when both exist.
    @Test
    func testPrefersPerFileObjectsOverWholeModuleFallback() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            try writeObject(buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o"))
            let debugDirectory = buildDirectory.deletingLastPathComponent()
            try writeObject(debugDirectory.appendingPathComponent("Runtime.o"))

            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory,
                scratchRootDirectory: scratchRoot
            )

            #expect(discovered.map(canonicalPath) == [
                canonicalPath(buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o").path),
            ])
        }
    }

    // The AST-wrapper object SwiftPM emits under "Modules/Runtime.o" (only
    // "__Swift_AST", no runtime code) and other targets' objects must not be
    // mistaken for the runtime object.
    @Test
    func testIgnoresModulesAstWrapperAndUnrelatedObjects() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let debugDirectory = buildDirectory.deletingLastPathComponent()
            let modulesDirectory = debugDirectory.appendingPathComponent("Modules", isDirectory: true)
            try FileManager.default.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
            try writeObject(modulesDirectory.appendingPathComponent("Runtime.o"))
            try writeObject(debugDirectory.appendingPathComponent("RuntimeABI.o"))

            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory,
                scratchRootDirectory: scratchRoot
            )

            #expect(discovered.isEmpty)
        }
    }

    // Accepts the alternate WMO object name some toolchains produce.
    @Test
    func testFallsBackToWholeModuleRuntimeSwiftObject() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let debugDirectory = buildDirectory.deletingLastPathComponent()
            let wmoObject = debugDirectory.appendingPathComponent("Runtime.swift.o")
            try writeObject(wmoObject)

            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory,
                scratchRootDirectory: scratchRoot
            )

            #expect(discovered.map(canonicalPath) == [canonicalPath(wmoObject.path)])
        }
    }
}
