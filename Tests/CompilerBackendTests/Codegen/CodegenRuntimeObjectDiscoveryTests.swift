@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenRuntimeObjectDiscoveryTests {
    private func withScratchLayout(
        configuration: RuntimeBuildConfiguration = .debug,
        _ body: (_ buildDirectory: URL, _ scratchRoot: URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let scratchRoot = fileManager.temporaryDirectory
            .appendingPathComponent("bug051-\(UUID().uuidString)", isDirectory: true)
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
    func testRuntimeSharedScratchRootIsCheckoutIndependentAndOverridable() throws {
        let home = URL(fileURLWithPath: "/tmp/kswiftk-home", isDirectory: true)
        let defaultRoot = CodegenRuntimeSupport.runtimeSharedScratchRoot(environment: [:], homeDirectory: home)
        #expect(defaultRoot.path.hasPrefix(home.path))
        #expect(defaultRoot.path.hasSuffix("kswiftk/runtime-build"))

        let overridden = CodegenRuntimeSupport.runtimeSharedScratchRoot(
            environment: ["KSWIFTK_RUNTIME_CACHE_DIR": "/tmp/custom-runtime-cache"],
            homeDirectory: home
        )
        #expect(overridden.path == "/tmp/custom-runtime-cache")

        let buildDirectory = try CodegenRuntimeSupport.runtimeBuildDirectory(
            target: TargetTriple.hostDefault(), configuration: .release
        )
        let packageRoot = try CodegenRuntimeSupport.runtimePackageRootURL()
        #expect(!buildDirectory.path.hasPrefix(packageRoot.path + "/"))
    }

    @Test
    func testRuntimeBuildConfigurationIsIncludedInArgumentsPathsAndCacheKeys() throws {
        let target = TargetTriple(
            arch: "arm64",
            vendor: "apple",
            os: "macosx",
            osVersion: nil
        )
        let debugDirectory = try CodegenRuntimeSupport.runtimeBuildDirectory(
            target: target,
            configuration: .debug
        )
        let releaseDirectory = try CodegenRuntimeSupport.runtimeBuildDirectory(
            target: target,
            configuration: .release
        )
        #expect(debugDirectory != releaseDirectory)
        #expect(debugDirectory.path.contains("/debug/"))
        #expect(releaseDirectory.path.contains("/release/"))

        let debugArguments = try CodegenRuntimeSupport.swiftBuildArguments(
            target: target,
            configuration: .debug
        )
        let releaseArguments = try CodegenRuntimeSupport.swiftBuildArguments(
            target: target,
            configuration: .release
        )
        #expect(debugArguments.contains { $0 == "debug" })
        #expect(releaseArguments.contains { $0 == "release" })
        #expect(debugArguments != releaseArguments)

        let debugCacheKey = try CodegenRuntimeSupport.runtimeBuildCacheKey(
            target: target,
            configuration: .debug
        )
        let releaseCacheKey = try CodegenRuntimeSupport.runtimeBuildCacheKey(
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
            let cacheKey = try CodegenRuntimeSupport.runtimeBuildCacheKey(
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

    @Test
    func testIncludesRuntimeABIDependencyObjects() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let runtimeObject = buildDirectory.appendingPathComponent("RuntimeStringHelpers.swift.o")
            try writeObject(runtimeObject)
            let abiDirectory = buildDirectory.deletingLastPathComponent()
                .appendingPathComponent("RuntimeABI.build", isDirectory: true)
            try FileManager.default.createDirectory(at: abiDirectory, withIntermediateDirectories: true)
            let abiObject = abiDirectory.appendingPathComponent("KotlinStringSurrogateEncoding.swift.o")
            try writeObject(abiObject)
            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory, scratchRootDirectory: scratchRoot
            )
            #expect(Set(discovered.map(canonicalPath)) == Set([runtimeObject.path, abiObject.path].map(canonicalPath)))
        }
    }

    @Test
    func testIncludesWholeModuleRuntimeABIDependency() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let directory = buildDirectory.deletingLastPathComponent()
            let runtimeObject = directory.appendingPathComponent("Runtime.o")
            let abiObject = directory.appendingPathComponent("RuntimeABI.o")
            try writeObject(runtimeObject)
            try writeObject(abiObject)
            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory, scratchRootDirectory: scratchRoot
            )
            #expect(Set(discovered.map(canonicalPath)) == Set([runtimeObject.path, abiObject.path].map(canonicalPath)))
        }
    }

    @Test
    func testIncludesRuntimeABIDependencyInSwiftBuildLayout() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let directory = buildDirectory.deletingLastPathComponent()
            let runtimeDirectory = directory.appendingPathComponent("Runtime-t.build/Objects-normal/arm64")
            let abiDirectory = directory.appendingPathComponent("RuntimeABI-t.build/Objects-normal/arm64")
            try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: abiDirectory, withIntermediateDirectories: true)
            let runtimeObject = runtimeDirectory.appendingPathComponent("Runtime.o")
            let abiObject = abiDirectory.appendingPathComponent("RuntimeABI.o")
            try writeObject(runtimeObject)
            try writeObject(abiObject)
            let discovered = CodegenRuntimeSupport.discoverRuntimeObjectPaths(
                inScratchBuildDirectory: buildDirectory, scratchRootDirectory: scratchRoot
            )
            #expect(Set(discovered.map(canonicalPath)) == Set([runtimeObject.path, abiObject.path].map(canonicalPath)))
        }
    }

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

    @Test
    func testObjectsWithoutManifestAreNotACacheHit() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            try writeObject(buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o"))
            let manifestURL = scratchRoot.appendingPathComponent("objects-debug.manifest")

            let validated = CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(
                manifestURL: manifestURL
            )

            #expect(validated.isEmpty)
        }
    }

    @Test
    func testManifestRoundTripValidatesExistingObjects() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let first = buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o")
            let second = buildDirectory.appendingPathComponent("RuntimeSequence.swift.o")
            try writeObject(first)
            try writeObject(second)
            let manifestURL = scratchRoot.appendingPathComponent("objects-debug.manifest")

            try CodegenRuntimeSupport.writeRuntimeObjectsManifest(
                [first.path, second.path],
                to: manifestURL
            )
            let validated = CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(
                manifestURL: manifestURL
            )

            #expect(validated == [first.path, second.path])
        }
    }

    @Test
    func testManifestListingMissingObjectIsStale() throws {
        try withScratchLayout { buildDirectory, scratchRoot in
            let survivor = buildDirectory.appendingPathComponent("RuntimeArrayBasics.swift.o")
            let removed = buildDirectory.appendingPathComponent("RuntimeSequence.swift.o")
            try writeObject(survivor)
            let manifestURL = scratchRoot.appendingPathComponent("objects-debug.manifest")

            try CodegenRuntimeSupport.writeRuntimeObjectsManifest(
                [survivor.path, removed.path],
                to: manifestURL
            )
            let validated = CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(
                manifestURL: manifestURL
            )

            #expect(validated.isEmpty)
        }
    }

    @Test
    func testEmptyManifestIsACacheMiss() throws {
        try withScratchLayout { _, scratchRoot in
            let manifestURL = scratchRoot.appendingPathComponent("objects-debug.manifest")
            try CodegenRuntimeSupport.writeRuntimeObjectsManifest([], to: manifestURL)

            let validated = CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(
                manifestURL: manifestURL
            )

            #expect(validated.isEmpty)
        }
    }

    @Test
    func testRuntimeBuildTimeoutDefaultsWhenEnvironmentVariableIsAbsent() {
        let timeout = CodegenRuntimeSupport.runtimeBuildTimeoutSeconds(environment: [:])
        #expect(timeout == 600)
    }

    @Test
    func testRuntimeBuildTimeoutUsesEnvironmentVariableOverride() {
        let timeout = CodegenRuntimeSupport.runtimeBuildTimeoutSeconds(
            environment: ["KSWIFTK_RUNTIME_BUILD_TIMEOUT": "900"]
        )
        #expect(timeout == 900)
    }

    @Test(arguments: ["not-a-number", "0", "-5", "", "inf", "nan"])
    func testRuntimeBuildTimeoutIgnoresInvalidOverride(rawValue: String) {
        let timeout = CodegenRuntimeSupport.runtimeBuildTimeoutSeconds(
            environment: ["KSWIFTK_RUNTIME_BUILD_TIMEOUT": rawValue]
        )
        #expect(timeout == 600)
    }

    private func makeFakeRuntimePackageRoot(
        manifest: String = """
        // swift-tools-version: 6.2
        import PackageDescription
        let package = Package(name: "KSwiftK")
        """
    ) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("kuu788-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        for component in ["Sources/Runtime", "Sources/RuntimeABI", "Sources/RuntimeCAtomics", "Sources/CSQLite"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    @Test
    func testPackageRootSearchStartsAreCompilerOwned() {
        let fakeExecutable = URL(fileURLWithPath: "/opt/kswiftk/bin/kswiftc")
        let starts = CodegenRuntimeSupport.runtimePackageRootSearchStarts(
            executableURL: fakeExecutable
        )
        #expect(starts == [
            fakeExecutable.deletingLastPathComponent(),
            CodegenRuntimeSupport.runtimeSourceCheckoutRootURL,
        ])
    }

    @Test
    func testPackageRootResolvesToVerifiedCompilerOwnedCheckout() throws {
        let root = try CodegenRuntimeSupport.runtimePackageRootURL(environment: [:])
        #expect(CodegenRuntimeSupport.runtimePackageRootRejection(root) == nil)
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Runtime").path
            )
        )
    }

    @Test
    func testOverridePackageRootIsAcceptedWhenVerified() throws {
        let root = try makeFakeRuntimePackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for overridePath in [root.path, root.appendingPathComponent("Sources/Runtime").path] {
            let resolved = try CodegenRuntimeSupport.runtimePackageRootURL(
                environment: ["KSWIFTK_PACKAGE_ROOT": overridePath]
            )
            #expect(resolved.standardizedFileURL == root.standardizedFileURL)
        }
    }

    @Test
    func testOverridePackageRootRejectsNonKSwiftKManifest() throws {
        let root = try makeFakeRuntimePackageRoot(
            manifest: """
            // swift-tools-version: 6.2
            import PackageDescription
            let package = Package(name: "DefinitelyNotKSwiftK")
            """
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: CodegenRuntimeSupportError.self) {
            try CodegenRuntimeSupport.runtimePackageRootURL(
                environment: ["KSWIFTK_PACKAGE_ROOT": root.path]
            )
        }
    }

    @Test
    func testOverridePackageRootRejectsWorldWritableTree() throws {
        let root = try makeFakeRuntimePackageRoot()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: root.path
            )
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777],
            ofItemAtPath: root.path
        )

        #expect(throws: CodegenRuntimeSupportError.self) {
            try CodegenRuntimeSupport.runtimePackageRootURL(
                environment: ["KSWIFTK_PACKAGE_ROOT": root.path]
            )
        }
    }

    @Test
    func testOverridePackageRootRejectsMissingRuntimeSources() throws {
        let root = try makeFakeRuntimePackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("Sources/Runtime", isDirectory: true)
        )

        #expect(throws: CodegenRuntimeSupportError.self) {
            try CodegenRuntimeSupport.runtimePackageRootURL(
                environment: ["KSWIFTK_PACKAGE_ROOT": root.path]
            )
        }
    }

    @Test
    func testOverridePackageRootRejectsPathWithoutManifest() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuu788-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(throws: CodegenRuntimeSupportError.self) {
            try CodegenRuntimeSupport.runtimePackageRootURL(
                environment: ["KSWIFTK_PACKAGE_ROOT": empty.path]
            )
        }
    }

    @Test
    func testWorkingDirectoryManifestIsNotEvaluated() throws {
        let fileManager = FileManager.default
        let fakeRoot = try makeFakeRuntimePackageRoot()
        defer { try? fileManager.removeItem(at: fakeRoot) }

        let original = fileManager.currentDirectoryPath
        _ = fileManager.changeCurrentDirectoryPath(fakeRoot.path)
        defer { _ = fileManager.changeCurrentDirectoryPath(original) }

        let resolved = try CodegenRuntimeSupport.runtimePackageRootURL(environment: [:])
        #expect(resolved.standardizedFileURL != fakeRoot.standardizedFileURL)
    }

    @Test
    func testRuntimeBuildDoesNotDisableSandbox() throws {
        let arguments = try CodegenRuntimeSupport.swiftBuildArguments(
            target: .hostDefault(),
            configuration: .release
        )
        #expect(!arguments.contains("--disable-sandbox"))
    }

    @Test
    func testRuntimeSourceFingerprintPersistsAcrossCallsAndTracksContent() throws {
        let fileManager = FileManager.default
        let packageRoot = try makeFakeRuntimePackageRoot()
        defer { try? fileManager.removeItem(at: packageRoot) }
        let scratchRoot = fileManager.temporaryDirectory
            .appendingPathComponent("runtimefp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratchRoot) }

        let runtimeFile = packageRoot
            .appendingPathComponent("Sources/Runtime/RuntimeArrayBasics.swift")
        let abiFile = packageRoot
            .appendingPathComponent("Sources/RuntimeABI/RuntimeABIStubs.swift")
        try "func runtimeA() {}".write(to: runtimeFile, atomically: true, encoding: .utf8)
        try "func abiB() {}".write(to: abiFile, atomically: true, encoding: .utf8)

        let first = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )
        #expect(fileManager.fileExists(
            atPath: scratchRoot.appendingPathComponent("source-fingerprints.json").path
        ))

        let second = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )
        #expect(second == first)

        try "func runtimeA() { print(1) }".write(
            to: runtimeFile, atomically: true, encoding: .utf8
        )
        let edited = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )
        #expect(edited != first)

        try fileManager.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: runtimeFile.path
        )
        let retouched = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )
        #expect(retouched == edited)
    }

    @Test
    func testPersistedRuntimeFingerprintHitReadsNoFileContents() throws {
        let fileManager = FileManager.default
        let packageRoot = try makeFakeRuntimePackageRoot()
        defer { try? fileManager.removeItem(at: packageRoot) }
        let scratchRoot = fileManager.temporaryDirectory
            .appendingPathComponent("runtimefp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratchRoot) }

        let runtimeFile = packageRoot
            .appendingPathComponent("Sources/Runtime/RuntimeArrayBasics.swift")
        try "func runtimeA() {}".write(to: runtimeFile, atomically: true, encoding: .utf8)

        let first = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )

        try fileManager.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: runtimeFile.path
        )
        defer {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: runtimeFile.path
            )
        }

        let second = try CodegenRuntimeSupport.runtimeSourceFingerprint(
            packageRoot: packageRoot, scratchRoot: scratchRoot
        )
        #expect(second == first)
    }
}
