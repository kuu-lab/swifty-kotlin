@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct StdlibArtifactCacheTests {
    @Test
    func packagedCandidatesCoverDeveloperAndInstalledLayouts() {
        let candidates = StdlibArtifactCache.packagedArtifactCandidates(
            executablePath: "/opt/kswiftk/bin/kswiftc"
        )

        #expect(candidates.contains("/opt/kswiftk/bin/KSwiftKStdlib.kklib"))
        #expect(candidates.contains("/opt/kswiftk/bin/stdlib/KSwiftKStdlib.kklib"))
        #expect(candidates.contains("/opt/kswiftk/bin/KSwiftK_CompilerCore.resources/KSwiftKStdlib.kklib"))
        #expect(candidates.contains(
            "/opt/kswiftk/bin/KSwiftK_CompilerCore.bundle/Contents/Resources/KSwiftKStdlib.kklib"
        ))
        #expect(candidates.contains("/opt/kswiftk/lib/kswiftk/stdlib/KSwiftKStdlib.kklib"))
        #expect(Set(candidates).count == candidates.count)
    }

    @Test
    func sharedBuilderProducesAValidatedStdlibManifest() throws {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-stdlib-cache-test-\(UUID().uuidString)")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputBase + ".kklib")
        }

        let artifactPath = try StdlibArtifactBuilder.build(
            outputBase: outputBase,
            target: TargetTriple.hostDefault()
        )
        let manifestPath = URL(fileURLWithPath: artifactPath)
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestPath)
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(manifest["formatVersion"] as? Int == 1)
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["libraryKind"] as? String == "stdlib")
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        #expect(manifest["target"] as? String == "\(TargetTriple.hostDefault().arch)-\(TargetTriple.hostDefault().vendor)-\(TargetTriple.hostDefault().os)")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
    }

    // MARK: - Cache recovery (KUU-1426)

    /// A cached artifact whose manifest references an inline-KIR blob that is
    /// no longer on disk must be rebuilt instead of being handed to a compile
    /// that would then fail with KSWIFTK-LIB-0019 or missing link symbols.
    @Test
    func cachedArtifactMissingInlineKIRBlobIsRebuilt() throws {
        let fm = FileManager.default
        let cacheDirectory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()
        var buildCount = 0

        let artifactPath = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory
        ) { outputBase in
            buildCount += 1
            return try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline", "beta_inline"]
            )
        }
        #expect(buildCount == 1)

        // Simulate a blob lost between publish and the next compile: the
        // manifest and metadata still reference it.
        let missingBlob = artifactPath + "/inline-kir/"
            + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        try fm.removeItem(atPath: missingBlob)

        let rebuilt = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory
        ) { outputBase in
            buildCount += 1
            return try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline", "beta_inline"]
            )
        }

        #expect(buildCount == 2)
        #expect(rebuilt == artifactPath)
        #expect(fm.fileExists(atPath: missingBlob))
    }

    /// Compilers with different fingerprints must never replace one another's
    /// artifact paths, because a compile can load inline KIR after resolution.
    @Test
    func differentCompilerFingerprintsKeepArtifactsAtSeparatePaths() throws {
        let fm = FileManager.default
        let cacheDirectory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()
        var buildCounts: [String: Int] = [:]

        func resolve(fingerprint: String) throws -> String {
            try StdlibArtifactCache.resolveOrBuildCached(
                target: target,
                cacheDirectory: cacheDirectory,
                compilerFingerprint: fingerprint
            ) { outputBase in
                buildCounts[fingerprint, default: 0] += 1
                let path = try Self.writeFakeArtifact(
                    at: outputBase,
                    target: target,
                    inlineMangledNames: ["alpha_inline"]
                )
                try fingerprint.write(
                    toFile: path + "/compiler-id",
                    atomically: true,
                    encoding: .utf8
                )
                return path
            }
        }

        let firstPath = try resolve(fingerprint: "worktree-a")
        let secondPath = try resolve(fingerprint: "worktree-b")
        let firstPathAgain = try resolve(fingerprint: "worktree-a")

        #expect(firstPath != secondPath)
        #expect(firstPathAgain == firstPath)
        #expect(try String(contentsOfFile: firstPath + "/compiler-id", encoding: .utf8) == "worktree-a")
        #expect(try String(contentsOfFile: secondPath + "/compiler-id", encoding: .utf8) == "worktree-b")
        #expect(buildCounts["worktree-a"] == 1)
        #expect(buildCounts["worktree-b"] == 1)
    }

    /// A compile killed while the artifact was still building leaves only a
    /// `.building-*` staging tree and the (harmless) `.lock` file behind; the
    /// next resolve must ignore them and produce a valid artifact.
    @Test
    func interruptedBuildRemnantsDoNotBlockResolution() throws {
        let fm = FileManager.default
        let cacheDirectory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()

        var artifactParent: String?
        let artifactPath = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory
        ) { outputBase in
            artifactParent = URL(fileURLWithPath: outputBase).deletingLastPathComponent().path
            return try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline"]
            )
        }
        let parent = try #require(artifactParent)

        // Seed remnants a killed build would leave: a half-written staging
        // tree (manifest present, blobs never written) and a fresh one that
        // must not be swept because it could still belong to a live builder.
        let staleStaging = parent + "/KSwiftKStdlib.kklib.building-1-\(UUID().uuidString).kklib"
        let freshStaging = parent + "/KSwiftKStdlib.kklib.building-2-\(UUID().uuidString).kklib"
        try fm.createDirectory(atPath: staleStaging + "/inline-kir", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: freshStaging, withIntermediateDirectories: true)
        try fm.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)],
            ofItemAtPath: staleStaging
        )

        // A still-valid cached artifact is reused without rebuilding.
        var buildCount = 0
        let resolved = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory
        ) { outputBase in
            buildCount += 1
            return try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline"]
            )
        }
        #expect(buildCount == 0)
        #expect(resolved == artifactPath)

        // Force a rebuild by removing a blob and confirm the ancient staging
        // tree is reclaimed while the fresh one is left alone.
        let missingBlob = artifactPath + "/inline-kir/"
            + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        try fm.removeItem(atPath: missingBlob)
        _ = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory
        ) { outputBase in
            buildCount += 1
            return try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline"]
            )
        }
        #expect(buildCount == 1)
        #expect(!fm.fileExists(atPath: staleStaging))
        #expect(fm.fileExists(atPath: freshStaging))
        // The freshly published artifact is intact.
        #expect(fm.fileExists(
            atPath: artifactPath + "/inline-kir/"
                + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        ))
    }

    /// A failed rebuild must not delete the artifact that is already in
    /// place: the previous entry stays until a validated replacement exists.
    @Test
    func failedRebuildKeepsExistingArtifact() throws {
        let fm = FileManager.default
        let cacheDirectory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()

        let artifactPath = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory,
            compilerFingerprint: "worktree-a"
        ) { outputBase in
            try Self.writeFakeArtifact(
                at: outputBase,
                target: target,
                inlineMangledNames: ["alpha_inline"]
            )
        }

        struct FakeBuildError: Error {}
        #expect(throws: (any Error).self) {
            try StdlibArtifactCache.resolveOrBuildCached(
                target: target,
                cacheDirectory: cacheDirectory,
                compilerFingerprint: "worktree-b"
            ) { _ in
                throw FakeBuildError()
            }
        }
        #expect(fm.fileExists(atPath: artifactPath + "/manifest.json"))
        #expect(fm.fileExists(
            atPath: artifactPath + "/inline-kir/"
                + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        ))
    }

    /// A build that produces a structurally incomplete artifact must not
    /// publish it; the staging tree is cleaned up instead.
    @Test
    func invalidBuilderOutputIsNotPublished() throws {
        let fm = FileManager.default
        let cacheDirectory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()

        #expect(throws: (any Error).self) {
            try StdlibArtifactCache.resolveOrBuildCached(
                target: target,
                cacheDirectory: cacheDirectory
            ) { outputBase in
                // Build "succeeds" but never writes the referenced blob.
                try Self.writeFakeArtifact(
                    at: outputBase,
                    target: target,
                    inlineMangledNames: ["alpha_inline"],
                    omitBlobs: ["alpha_inline"]
                )
            }
        }

        let keyDirectory = cacheDirectory
            .appendingPathComponent("kswiftk", isDirectory: true)
            .appendingPathComponent("stdlib", isDirectory: true)
        let keyDirs = try fm.contentsOfDirectory(
            at: keyDirectory,
            includingPropertiesForKeys: nil
        )
        for keyDir in keyDirs {
            let entries = try fm.contentsOfDirectory(atPath: keyDir.path)
            #expect(entries == ["KSwiftKStdlib.kklib.lock"])
        }
    }

    private func makeTemporaryCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-cache-test-\(UUID().uuidString)", isDirectory: true)
    }

    /// Writes the smallest artifact `validateArtifact` accepts: manifest,
    /// metadata index, one object file, and one `.kirbin` per `inline=1`
    /// record (minus `omitBlobs`).
    private static func writeFakeArtifact(
        at outputBase: String,
        target: TargetTriple,
        inlineMangledNames: [String],
        omitBlobs: Set<String> = []
    ) throws -> String {
        let fm = FileManager.default
        let artifactPath = outputBase + ".kklib"
        try fm.createDirectory(
            atPath: artifactPath + "/inline-kir",
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            atPath: artifactPath + "/objects",
            withIntermediateDirectories: true
        )
        try Data().write(to: URL(fileURLWithPath: artifactPath + "/objects/KSwiftKStdlib_0.o"))

        var lines = [
            "kklib-metadata-v2",
            "records=\(inlineMangledNames.count)",
            "index",
        ]
        for (index, name) in inlineMangledNames.enumerated() {
            lines.append(
                "\(index)\t0\tfunction \(name) fq=test.\(name) schema=v1 arity=0 suspend=0 inline=1 operator=0 infix=0"
            )
        }
        lines.append("body")
        try lines.joined(separator: "\n").write(
            toFile: artifactPath + "/metadata.bin",
            atomically: true,
            encoding: .utf8
        )

        for name in inlineMangledNames where !omitBlobs.contains(name) {
            try Data().write(
                to: URL(
                    fileURLWithPath: artifactPath + "/inline-kir/"
                        + MetadataEncoder.inlineKIRFileName(for: name)
                )
            )
        }

        let manifest: [String: Any] = [
            "formatVersion": 1,
            "moduleName": "KSwiftKStdlib",
            "libraryKind": "stdlib",
            "kotlinLanguageVersion": "2.3.10",
            "compilerVersion": CompilerBuildInfo.version,
            "target": "\(target.arch)-\(target.vendor)-\(target.os)",
            "stdlibManifestHash": BundledStdlib.manifestHash(),
            "objects": ["objects/KSwiftKStdlib_0.o"],
            "metadata": "metadata.bin",
            "inlineKIRDir": "inline-kir",
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: URL(fileURLWithPath: artifactPath + "/manifest.json"))
        return artifactPath
    }
}
