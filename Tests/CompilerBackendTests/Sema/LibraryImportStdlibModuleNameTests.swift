#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct LibraryImportStdlibModuleNameTests {
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
            let inlineFns = ImportedInlineFunctionStore()
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: inlineFns
            )

            let stdlibModuleName = try #require(work.stdlibModuleName)
            let manifest = try JSONDecoder().decode(
                LibraryManifest.self,
                from: Data(contentsOf: libDir.appendingPathComponent("manifest.json"))
            )
            let expectedModuleName = try #require(manifest.moduleName)
            #expect(stdlibModuleName == ctx.interner.intern(expectedModuleName))
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
            let inlineFns = ImportedInlineFunctionStore()
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: inlineFns
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
            let inlineFns = ImportedInlineFunctionStore()
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: inlineFns
            )
            let stdlibModuleName = try #require(work.stdlibModuleName)

            let expectedKeys = Set(
                symbols.allSymbols()
                    .filter { $0.flags.contains(.importedLibrary) }
                    .lazy
                    .compactMap { symbol -> BundledMemberKey? in
                        guard symbols.moduleFQN(for: symbol.id) == stdlibModuleName else { return nil }
                        guard let key = BundledDeclarationIndex.memberKey(
                            for: symbol,
                            symbolID: symbol.id,
                            symbols: symbols,
                            types: types,
                            interner: ctx.interner
                        ) else { return nil }
                        return key
                    }
            )
            #expect(!expectedKeys.isEmpty)

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

            for key in expectedKeys {
                #expect(mergedIndex.contains(key))
            }
        }
    }
}
#endif
