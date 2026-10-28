#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Legacy snapshot archive coverage. Normal stdlib artifacts now use
/// compact-indexed lazy imports and do not emit or consume this archive.
@Suite
struct StdlibSemaSnapshotArchiveTests {
    private let target = TargetTriple.hostDefault()

    // MARK: - load gating

    @Test
    func schemaOneSnapshotIsRejected() throws {
        let dir = try makeArtifactDirectory(inlineBlobNames: ["alpha.kirbin"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = try makePayload(
            schemaVersion: 1,
            artifact: dir,
            relativePaths: ["inline-kir/alpha.kirbin"]
        )
        try writeSnapshot(payload, to: dir)

        #expect(load(artifact: dir) == nil)
    }

    @Test
    func currentSchemaSnapshotLoadsItsInlineDescriptors() throws {
        let dir = try makeArtifactDirectory(inlineBlobNames: ["alpha.kirbin", "beta.kirbin"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = try makePayload(
            schemaVersion: StdlibSemaSnapshotArchive.schemaVersion,
            artifact: dir,
            relativePaths: ["inline-kir/alpha.kirbin", "inline-kir/beta.kirbin"]
        )
        try writeSnapshot(payload, to: dir)

        let loaded = try #require(load(artifact: dir))
        #expect(loaded.inlineFunctions.count == 2)
        #expect(
            Set(loaded.inlineFunctions.map(\.relativePath))
                == ["inline-kir/alpha.kirbin", "inline-kir/beta.kirbin"]
        )
    }

    @Test
    func snapshotReferencingAMissingInlineBlobIsRejected() throws {
        let dir = try makeArtifactDirectory(inlineBlobNames: ["alpha.kirbin"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = try makePayload(
            schemaVersion: StdlibSemaSnapshotArchive.schemaVersion,
            artifact: dir,
            relativePaths: ["inline-kir/alpha.kirbin", "inline-kir/lost.kirbin"]
        )
        try writeSnapshot(payload, to: dir)

        #expect(load(artifact: dir) == nil)
    }

    // MARK: - write capture

    /// The capture compile defers every compact-indexed inline body, so the
    /// snapshot must register a descriptor per pending binding — the bug was
    /// that only eagerly-imported `$default` stubs were serialised.
    @Test
    func writeCapturesEveryDeferredInlineDescriptor() throws {
        let dir = try makeFakeArtifact(inlineMangledNames: ["alpha_inline", "beta_inline"])
        defer { try? FileManager.default.removeItem(at: dir) }

        try StdlibSemaSnapshotArchive.write(forArtifactAt: dir.path, target: target)

        let snapshot = try #require(load(artifact: dir))
        #expect(snapshot.inlineFunctions.count == 2)
        #expect(Set(snapshot.inlineFunctions.map(\.name)) == ["alpha_inline", "beta_inline"])
    }

    /// A snapshot already inside the artifact must not short-circuit the
    /// rewrite's own capture compile: the second write rebuilds the import
    /// state from the index and still emits every descriptor.
    @Test
    func rewritingOverAnExistingSnapshotKeepsAllDescriptors() throws {
        let dir = try makeFakeArtifact(inlineMangledNames: ["alpha_inline"])
        defer { try? FileManager.default.removeItem(at: dir) }

        try StdlibSemaSnapshotArchive.write(forArtifactAt: dir.path, target: target)
        try StdlibSemaSnapshotArchive.write(forArtifactAt: dir.path, target: target)

        let snapshot = try #require(load(artifact: dir))
        #expect(snapshot.inlineFunctions.map(\.name) == ["alpha_inline"])
    }

    // MARK: - fixtures

    private func load(artifact dir: URL) -> SemaSnapshotArchivePayload? {
        StdlibSemaSnapshotArchive.load(
            from: dir.path,
            metadataPath: dir.appendingPathComponent("metadata.bin").path,
            target: target,
            moduleName: "KSwiftKStdlib"
        )
    }

    private func makeArtifactDirectory(inlineBlobNames: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sema-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(
            at: dir.appendingPathComponent("inline-kir"),
            withIntermediateDirectories: true
        )
        try Data("metadata".utf8).write(to: dir.appendingPathComponent("metadata.bin"))
        for name in inlineBlobNames {
            try Data().write(to: dir.appendingPathComponent("inline-kir/\(name)"))
        }
        return dir
    }

    private func makePayload(
        schemaVersion: Int,
        artifact dir: URL,
        relativePaths: [String]
    ) throws -> SemaSnapshotArchivePayload {
        let metadata = try Data(contentsOf: dir.appendingPathComponent("metadata.bin"))
        return SemaSnapshotArchivePayload(
            schemaVersion: schemaVersion,
            compilerVersion: CompilerBuildInfo.version,
            target: "\(target.arch)-\(target.vendor)-\(target.os)",
            moduleName: "KSwiftKStdlib",
            metadataFingerprint: StdlibSemaSnapshotArchive.fingerprint(metadata),
            symbols: SymbolTable().makeSemaSnapshot(interner: StringInterner()),
            types: TypeSystem().makeSemaSnapshot(),
            inlineFunctions: relativePaths.enumerated().map { index, path in
                SemaSnapshotInlineFunction(
                    symbol: SymbolID(rawValue: Int32(index)),
                    relativePath: path,
                    signature: nil,
                    name: path,
                    reifiedComponentTokens: false,
                    packedValueParameterTypes: nil
                )
            }
        )
    }

    private func writeSnapshot(
        _ payload: SemaSnapshotArchivePayload,
        to dir: URL
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(payload)
            .write(to: dir.appendingPathComponent(StdlibSemaSnapshotArchive.fileName))
    }

    /// The smallest artifact the snapshot writer can capture from: a compact
    /// v2 metadata index of inline function records plus one `.kirbin` blob
    /// per record, mirroring `writeFakeArtifact` in `StdlibArtifactCacheTests`.
    private func makeFakeArtifact(inlineMangledNames: [String]) throws -> URL {
        let fm = FileManager.default
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("sema-snapshot-write-\(UUID().uuidString)")
        let artifact = outputBase.appendingPathExtension("kklib")
        try fm.createDirectory(
            at: artifact.appendingPathComponent("inline-kir"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: artifact.appendingPathComponent("objects"),
            withIntermediateDirectories: true
        )
        try Data().write(to: artifact.appendingPathComponent("objects/KSwiftKStdlib_0.o"))

        let records = inlineMangledNames.map {
            MetadataRecord(
                kind: .function,
                mangledName: $0,
                fqName: "test.\($0)",
                isInline: true
            )
        }
        try MetadataEncoder().serializeCompactIndexed(records)
            .write(to: artifact.appendingPathComponent("metadata.bin"))

        for name in inlineMangledNames {
            try Data().write(
                to: artifact.appendingPathComponent(
                    "inline-kir/\(MetadataEncoder.inlineKIRFileName(for: name))"
                )
            )
        }

        let manifest: [String: Any] = [
            "formatVersion": 2,
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
            .write(to: artifact.appendingPathComponent("manifest.json"))
        return artifact
    }
}
#endif
