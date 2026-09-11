#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression coverage for threading the stdlib artifact's module name
/// through `LibraryImportDeferredWork` instead of having
/// `mergeImportedStdlibSymbolsIntoBundledIndex` re-read and re-parse
/// manifest.json itself.
///
/// The second, independent read had no diagnostic on failure (unlike the
/// first, in `loadImportedLibrarySymbols` / `resolveLibraryManifestInfo`,
/// which emits KSWIFTK-LIB-0015/0020) — it silently returned `bundledIndex`
/// unchanged. Any synthetic-stub suppression keyed off that index (e.g.
/// `HeaderHelpers+SyntheticRangeUntilStubs`, which checks
/// `bundledIndex.contains(...)` before registering a concrete fallback stub)
/// would then fail open: the stub gets registered even though the artifact
/// already provides the real declaration, and the stub — being more
/// specific — wins overload resolution over the intended generic/imported
/// member. That is the shape of the CI-observed golden divergences this fix
/// targets (e.g. `in_range_operators.kt` resolving to the concrete
/// `Int.rangeUntil` stub instead of the generic `T.rangeUntil` member).
@Suite
struct LibraryImportStdlibModuleNameTests {
    /// Copies the shared stdlib artifact (built once per test process by
    /// `TestStdlibCache`) into a fresh directory so a test that mutates it
    /// (deleting manifest.json) can't affect other tests reusing the shared
    /// build.
    private func copyOfSharedStdlibArtifact() throws -> URL {
        let source = try testStdlibArtifactPath()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kklib")
        try FileManager.default.copyItem(atPath: source, toPath: destination.path)
        return destination
    }

    @Test
    func loadImportedLibrarySymbolsResolvesStdlibModuleNameFromTheSharedArtifact() throws {
        let libDir = try copyOfSharedStdlibArtifact()
        defer { try? FileManager.default.removeItem(at: libDir) }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "StdlibModuleNameApp",
                emit: .kirDump,
                stdlibLibraryPath: libDir.path
            )

            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: &inlineFns
            )

            let stdlibModuleName = try #require(work.stdlibModuleName)
            #expect(ctx.interner.resolve(stdlibModuleName) == "KSwiftKStdlib")
            #expect(
                !diagnostics.hasError,
                "Unexpected import errors: \(diagnostics.diagnostics.map(\.message).joined(separator: "\n"))"
            )
        }
    }

    @Test
    func stdlibModuleNameIsNilWithoutAStdlibLibraryPath() throws {
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoStdlibPathApp",
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )

            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: &inlineFns
            )

            #expect(work.stdlibModuleName == nil)
        }
    }

    @Test
    func mergeUsesTheThreadedModuleNameEvenAfterManifestJSONIsDeleted() throws {
        let libDir = try copyOfSharedStdlibArtifact()
        defer { try? FileManager.default.removeItem(at: libDir) }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MergeAfterDeleteApp",
                emit: .kirDump,
                stdlibLibraryPath: libDir.path
            )

            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: &inlineFns
            )
            let stdlibModuleName = try #require(work.stdlibModuleName)

            // Pick an imported symbol the same way the merge loop itself
            // does, so the expected key is derived rather than guessed.
            let (_, expectedKey) = try #require(
                symbols.allSymbols()
                    .filter { $0.flags.contains(.importedLibrary) }
                    .lazy
                    .compactMap { symbol -> (SemanticSymbol, BundledMemberKey)? in
                        guard symbols.moduleFQN(for: symbol.id) == stdlibModuleName else { return nil }
                        guard let key = BundledDeclarationIndex.memberKey(
                            for: symbol,
                            symbolID: symbol.id,
                            symbols: symbols,
                            types: types,
                            interner: ctx.interner
                        ) else { return nil }
                        return (symbol, key)
                    }
                    .first
            )

            // The regression scenario: manifest.json is gone by the time the
            // merge step runs (e.g. a concurrent rebuild elsewhere replaced
            // it, or it was transiently unreadable). Before this fix,
            // `mergeImportedStdlibSymbolsIntoBundledIndex` re-read and
            // re-parsed manifest.json itself and would have silently
            // returned `bundledIndex` unchanged here.
            let manifestPath = libDir.appendingPathComponent("manifest.json")
            try FileManager.default.removeItem(at: manifestPath)
            #expect(!FileManager.default.fileExists(atPath: manifestPath.path))

            let mergedIndex = phase.mergeImportedStdlibSymbolsIntoBundledIndex(
                bundledIndex: .empty,
                stdlibModuleName: stdlibModuleName,
                symbols: symbols,
                types: types,
                interner: ctx.interner
            )

            #expect(mergedIndex.contains(expectedKey))
        }
    }
}
#endif
