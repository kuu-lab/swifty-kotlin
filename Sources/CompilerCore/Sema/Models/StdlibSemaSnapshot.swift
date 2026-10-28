import Foundation

struct SemaSnapshotInlineFunction: Codable {
    let symbol: SymbolID
    let relativePath: String
    let signature: FunctionSignature?
    let name: String
    let reifiedComponentTokens: Bool
    let packedValueParameterTypes: [TypeID]?
}

struct SemaSnapshotArchivePayload: Codable {
    let schemaVersion: Int
    let compilerVersion: String
    let target: String
    let moduleName: String
    let metadataFingerprint: String
    let symbols: SymbolTableSemaSnapshot
    let types: TypeSystemSemaSnapshot
    let inlineFunctions: [SemaSnapshotInlineFunction]
}

func remapSnapshotSignature(
    _ signature: FunctionSignature,
    symbols symbolMap: [SymbolID: SymbolID],
    types typeMap: [TypeID: TypeID]
) -> FunctionSignature {
    func symbol(_ id: SymbolID) -> SymbolID { symbolMap[id] ?? id }
    func type(_ id: TypeID) -> TypeID { typeMap[id] ?? id }
    return FunctionSignature(
        receiverType: signature.receiverType.map(type),
        contextReceiverTypes: signature.contextReceiverTypes.map(type),
        contextParameterSymbols: signature.contextParameterSymbols.map(symbol),
        contextParameterTypes: signature.contextParameterTypes.map(type),
        parameterTypes: signature.parameterTypes.map(type),
        returnType: type(signature.returnType),
        isSuspend: signature.isSuspend,
        canThrow: signature.canThrow,
        valueParameterSymbols: signature.valueParameterSymbols.map(symbol),
        valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols
            .map { Set($0.map(symbol)) },
        valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
        valueParameterIsVararg: signature.valueParameterIsVararg,
        valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
        hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
        hasStableParameterNames: signature.hasStableParameterNames,
        typeParameterSymbols: signature.typeParameterSymbols.map(symbol),
        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
        typeParameterUpperBounds: signature.typeParameterUpperBounds.map { $0.map(type) },
        typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList.map { $0.map(type) },
        classTypeParameterCount: signature.classTypeParameterCount
    )
}

/// Legacy support for serializing a fully materialized stdlib Sema state.
/// The normal artifact builder and importer now use compact-indexed lazy loading.
public enum StdlibSemaSnapshotArchive {
    static let fileName = "sema.snapshot"
    // v2: snapshots written by schema 1 omitted the deferred inline-body
    // descriptors (only eagerly registered `$default` stubs were captured),
    // so consumers of such an artifact could not expand any stdlib inline
    // call and failed at link time. Rejecting them here falls the import
    // back to the compact-index lazy path, which registers every pending
    // binding correctly.
    static let schemaVersion = 2

    /// Builds a clean import context and writes its complete Sema state into
    /// the artifact. This is retained for archive tests and explicit tooling.
    public static func write(
        forArtifactAt artifactPath: String,
        target: TargetTriple,
        profile: StdlibProfile = .full
    ) throws {
        let root = URL(fileURLWithPath: artifactPath).standardizedFileURL
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: manifestData),
              let moduleName = manifest.moduleName,
              let relativeMetadataPath = manifest.metadata,
              let metadataURL = CompilerFileSystem.containedURL(relativePath: relativeMetadataPath, under: root),
              CompilerFileSystem.isRegularFile(at: metadataURL)
        else {
            throw SnapshotError.invalidArtifact("manifest or metadata is unavailable")
        }
        guard let metadata = try? Data(contentsOf: metadataURL, options: .mappedIfSafe) else {
            throw SnapshotError.invalidArtifact("metadata is unreadable")
        }

        // A snapshot already sitting in the artifact would be loaded by the
        // capture compile below and short-circuit the lazy import, leaving no
        // pending inline bindings to serialise — the rewrite would inherit
        // the old snapshot's gaps. Remove it so the capture always rebuilds
        // the full import state. The snapshot file is regenerated atomically
        // at the end of this function; a failed capture simply leaves the
        // artifact on the lazy path.
        let snapshotURL = root.appendingPathComponent(fileName)
        if CompilerFileSystem.isRegularFile(at: snapshotURL) {
            do {
                try FileManager.default.removeItem(at: snapshotURL)
            } catch {
                throw SnapshotError.write(
                    "Could not remove existing snapshot for rewrite: \(error.localizedDescription)"
                )
            }
        }

        let emptyInput = root.appendingPathComponent(".sema-snapshot-empty.kt").path
        let sourceManager = SourceManager()
        _ = sourceManager.addFile(path: emptyInput, contents: Data())
        let options = CompilerOptions(
            moduleName: "KSwiftKSemaSnapshot",
            inputs: [emptyInput],
            outputPath: root.appendingPathComponent(".sema-snapshot-output").path,
            emit: .executable,
            target: target,
            includeStdlib: false,
            stdlibLibraryPath: root.path,
            allowDefaultStdlibLibrary: false,
            stdlibProfile: profile
        )
        let context = CompilationContext(
            options: options,
            sourceManager: sourceManager,
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        do {
            try LoadSourcesPhase().run(context)
            try LexPhase().run(context)
            try ParsePhase().run(context)
            try BuildASTPhase().run(context)
            try DataFlowSemaPhase(capturingImportedStdlibSnapshot: true).run(context)
        } catch {
            throw SnapshotError.semaBuild(String(describing: error))
        }
        guard let sema = context.sema, !context.diagnostics.hasError else {
            let details = context.diagnostics.diagnostics
                .filter { $0.severity == .error }
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw SnapshotError.semaBuild(details.isEmpty ? "Sema did not produce a module" : details)
        }

        sema.symbols.materializeAllIndexedLibraryState()
        guard !context.diagnostics.hasError else {
            let details = context.diagnostics.diagnostics
                .filter { $0.severity == .error }
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw SnapshotError.semaBuild(details)
        }
        let inlineFunctions = try sema.importedInlineFunctions.descriptors
            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
            .map { symbol, descriptor in
                let path = URL(fileURLWithPath: descriptor.path).standardizedFileURL
                let relativePath = relativePath(of: path, under: root)
                guard let relativePath,
                      let contained = CompilerFileSystem.containedURL(relativePath: relativePath, under: root),
                      CompilerFileSystem.isRegularFile(at: contained)
                else {
                    throw SnapshotError.invalidArtifact("inline KIR path escaped the artifact")
                }
                return SemaSnapshotInlineFunction(
                    symbol: symbol,
                    relativePath: relativePath,
                    signature: descriptor.signature,
                    name: context.interner.resolve(descriptor.name),
                    reifiedComponentTokens: descriptor.reifiedComponentTokens,
                    packedValueParameterTypes: descriptor.packedValueParameterTypes
                )
            }
        let payload = SemaSnapshotArchivePayload(
            schemaVersion: schemaVersion,
            compilerVersion: CompilerBuildInfo.version,
            target: targetIdentifier(target),
            moduleName: moduleName,
            metadataFingerprint: fingerprint(metadata),
            symbols: sema.symbols.makeSemaSnapshot(interner: context.interner),
            types: sema.types.makeSemaSnapshot(),
            inlineFunctions: inlineFunctions
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encoded: Data
        do {
            encoded = try encoder.encode(payload)
        } catch {
            throw SnapshotError.encoding(String(describing: error))
        }
        do {
            try encoded.write(to: root.appendingPathComponent(fileName), options: .atomic)
        } catch {
            throw SnapshotError.write(String(describing: error))
        }
    }

    static func load(
        from artifactPath: String,
        metadataPath: String,
        target: TargetTriple,
        moduleName: String?
    ) -> SemaSnapshotArchivePayload? {
        let root = URL(fileURLWithPath: artifactPath).standardizedFileURL
        guard let snapshotURL = CompilerFileSystem.containedURL(relativePath: fileName, under: root),
              CompilerFileSystem.isRegularFile(at: snapshotURL),
              let data = try? Data(contentsOf: snapshotURL, options: .mappedIfSafe),
              let payload = try? PropertyListDecoder().decode(SemaSnapshotArchivePayload.self, from: data),
              let metadata = try? Data(contentsOf: URL(fileURLWithPath: metadataPath), options: .mappedIfSafe),
              payload.schemaVersion == schemaVersion,
              payload.compilerVersion == CompilerBuildInfo.version,
              payload.target == targetIdentifier(target),
              payload.moduleName == moduleName,
              payload.metadataFingerprint == fingerprint(metadata)
        else {
            return nil
        }
        for descriptor in payload.inlineFunctions {
            guard let url = CompilerFileSystem.containedURL(relativePath: descriptor.relativePath, under: root),
                  CompilerFileSystem.isRegularFile(at: url)
            else {
                return nil
            }
        }
        return payload
    }

    private enum SnapshotError: Error, CustomStringConvertible {
        case invalidArtifact(String)
        case semaBuild(String)
        case encoding(String)
        case write(String)

        var description: String {
            switch self {
            case let .invalidArtifact(message): "Invalid stdlib snapshot input: \(message)"
            case let .semaBuild(message): "Could not build stdlib Sema snapshot: \(message)"
            case let .encoding(message): "Could not encode stdlib Sema snapshot: \(message)"
            case let .write(message): "Could not write stdlib Sema snapshot: \(message)"
            }
        }
    }

    private static func targetIdentifier(_ target: TargetTriple) -> String {
        "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    static func fingerprint(_ data: Data) -> String {
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x9e3779b97f4a7c15
        for byte in data {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second ^= UInt64(byte) &+ 0x9e3779b97f4a7c15 &+ (second << 6) &+ (second >> 2)
        }
        return "\(data.count)-\(String(first, radix: 16))-\(String(second, radix: 16))"
    }

    private static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
