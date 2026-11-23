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

        #expect(manifest["formatVersion"] as? Int == 2)
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["libraryKind"] as? String == "stdlib")
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
        #expect(manifest["target"] as? String == "\(TargetTriple.hostDefault().arch)-\(TargetTriple.hostDefault().vendor)-\(TargetTriple.hostDefault().os)")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        #expect(manifest["bundledMemberIndex"] as? String == "bundled-members.bin")
        #expect(manifest["precomputedSyntheticStubs"] as? Bool == true)
        #expect(manifest["precomputedReflectionRecords"] as? Bool == true)
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/bundled-members.bin"))

        let snapshotURL = URL(fileURLWithPath: artifactPath).appendingPathComponent("sema.snapshot")
        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    @Test
    func additionalIntegrityValidationRebuildsCorruptedObjects() throws {
        let fm = FileManager.default
        let directory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: directory) }
        let target = TargetTriple.hostDefault()
        var buildCount = 0
        func resolve() throws -> String {
            try StdlibArtifactCache.resolveOrBuildCached(
                target: target, cacheDirectory: directory, compilerFingerprint: "diff-integrity",
                preserveInvalidArtifacts: true,
                additionalValidator: { DiffStdlibCache.isIntactArtifact(at: $0) }
            ) { base in
                buildCount += 1
                let artifact = try Self.writeFakeArtifact(at: base, target: target, inlineMangledNames: [])
                try DiffStdlibCache.sealArtifact(at: artifact)
                return artifact
            }
        }
        let path = try resolve()
        #expect(try resolve() == path)
        #expect(buildCount == 1)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path + "/manifest.json"))) as? [String: Any]
        let object = try #require((manifest?["objects"] as? [String])?.first)
        try Data("corrupted".utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent(object))
        let recovered = try resolve()
        #expect(recovered != path)
        #expect(buildCount == 2)
        #expect(fm.fileExists(atPath: path))
        #expect(!DiffStdlibCache.isIntactArtifact(at: path))
        #expect(DiffStdlibCache.isIntactArtifact(at: recovered))
        #expect(try resolve() == recovered)
        #expect(buildCount == 2)
    }

    @Test(arguments: [false, true])
    func cachedArtifactMissingInlineKIRBlobIsRebuilt(compact: Bool) throws {
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
                inlineMangledNames: ["alpha_inline", "beta_inline"], compact: compact
            )
        }
        #expect(buildCount == 1)

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
                inlineMangledNames: ["alpha_inline", "beta_inline"], compact: compact
            )
        }

        #expect(buildCount == 2)
        #expect(rebuilt == artifactPath)
        #expect(fm.fileExists(atPath: missingBlob))
    }

    @Test
    func cachedArtifactInlineKIRBlobSymlinkEscapeIsRebuilt() throws {
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
                inlineMangledNames: ["alpha_inline"]
            )
        }
        #expect(buildCount == 1)

        let outsideFile = cacheDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).bin")
        try Data("outside".utf8).write(to: outsideFile)
        defer { try? fm.removeItem(at: outsideFile) }

        let blobPath = artifactPath + "/inline-kir/"
            + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        try fm.removeItem(atPath: blobPath)
        try fm.createSymbolicLink(atPath: blobPath, withDestinationPath: outsideFile.path)

        let rebuilt = try StdlibArtifactCache.resolveOrBuildCached(
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

        #expect(buildCount == 2)
        #expect(rebuilt == artifactPath)
        #expect((try? fm.destinationOfSymbolicLink(atPath: blobPath)) == nil)
    }

    @Test
    func cachedArtifactInlineKIRBlobInternalSymlinkStaysValid() throws {
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
                inlineMangledNames: ["alpha_inline"]
            )
        }
        #expect(buildCount == 1)

        let blobPath = artifactPath + "/inline-kir/"
            + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        try fm.removeItem(atPath: blobPath)
        try fm.createSymbolicLink(
            atPath: blobPath,
            withDestinationPath: "../objects/KSwiftKStdlib_0.o"
        )

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

        #expect(buildCount == 1)
        #expect(resolved == artifactPath)
    }

    @Test
    func cachedArtifactInlineKIRBlobNonRegularFileIsRebuilt() throws {
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
                inlineMangledNames: ["alpha_inline"]
            )
        }
        #expect(buildCount == 1)

        let blobPath = artifactPath + "/inline-kir/"
            + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        try fm.removeItem(atPath: blobPath)
        try fm.createDirectory(atPath: blobPath, withIntermediateDirectories: true)

        let rebuilt = try StdlibArtifactCache.resolveOrBuildCached(
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

        #expect(buildCount == 2)
        #expect(rebuilt == artifactPath)
    }

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
        #expect(fm.fileExists(
            atPath: artifactPath + "/inline-kir/"
                + MetadataEncoder.inlineKIRFileName(for: "alpha_inline")
        ))
    }

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

    @Test(arguments: [false, true])
    func compactCacheChecksIndexButKeepsUnusedBodyLazy(corruptIndex: Bool) throws {
        let fm = FileManager.default
        let directory = makeTemporaryCacheDirectory()
        defer { try? fm.removeItem(at: directory) }
        let target = TargetTriple.hostDefault()
        var builds = 0
        func resolve() throws -> String {
            try StdlibArtifactCache.resolveOrBuildCached(target: target, cacheDirectory: directory) { base in
                builds += 1
                return try Self.writeFakeArtifact(
                    at: base, target: target, inlineMangledNames: ["test_inline"], compact: true
                )
            }
        }
        let artifact = try resolve()
        let metadata = URL(fileURLWithPath: artifact + "/metadata.bin")
        var data = try Data(contentsOf: metadata)
        if corruptIndex {
            let countOffset = "kklib-metadata-v3\n".utf8.count
            data.replaceSubrange(countOffset ..< countOffset + 4, with: repeatElement(UInt8(0xFF), count: 4))
        } else {
            data[data.count - 2] = 0xFF
        }
        try data.write(to: metadata)
        #expect(try resolve() == artifact)
        #expect(builds == (corruptIndex ? 2 : 1))
    }

    private func makeTemporaryCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-cache-test-\(UUID().uuidString)", isDirectory: true)
    }

    private static func writeFakeArtifact(
        at outputBase: String,
        target: TargetTriple,
        inlineMangledNames: [String],
        omitBlobs: Set<String> = [],
        compact: Bool = false
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
        if compact {
            let records = inlineMangledNames.map {
                MetadataRecord(kind: .function, mangledName: $0, fqName: "test.\($0)", isInline: true)
            }
            try MetadataEncoder().serializeCompactIndexed(records)
                .write(to: URL(fileURLWithPath: artifactPath + "/metadata.bin"))
        } else {
            try lines.joined(separator: "\n").write(
                toFile: artifactPath + "/metadata.bin", atomically: true, encoding: .utf8
            )
        }

        for name in inlineMangledNames where !omitBlobs.contains(name) {
            try Data().write(
                to: URL(
                    fileURLWithPath: artifactPath + "/inline-kir/"
                        + MetadataEncoder.inlineKIRFileName(for: name)
                )
            )
        }

        let manifest: [String: Any] = [
            "formatVersion": compact ? 2 : 1,
            "moduleName": "KSwiftKStdlib",
            "libraryKind": "stdlib",
            "kotlinLanguageVersion": "2.4.20",
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
