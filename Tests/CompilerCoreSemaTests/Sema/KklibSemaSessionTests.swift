@testable import CompilerCore
import Foundation
import Testing

@Suite("Sema.KklibSemaSession", .serialized)
struct KklibSemaSessionTests {
    @Test
    func cachedImportSnapshotBranchesWithoutLeakingRequestSymbols() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-sema-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: library) }
        try "{\"formatVersion\":2,\"metadata\":\"metadata.bin\"}"
            .write(to: library.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try Data([0]).write(to: library.appendingPathComponent("metadata.bin"))

        let options = CompilerOptions(
            moduleName: "SessionTest",
            inputs: [],
            outputPath: library.appendingPathComponent("out").path,
            emit: .executable,
            target: .hostDefault(),
            includeStdlib: false,
            stdlibLibraryPath: library.path
        )
        let interner = StringInterner()
        let symbols = SymbolTable()
        let importedName = interner.intern("stdlibEntry")
        let importedSymbol = symbols.define(
            kind: .function,
            name: importedName,
            fqName: [interner.intern("kotlin"), importedName],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        let types = TypeSystem()
        types.symbolTable = symbols
        let importWork = DataFlowSemaPhase.LibraryImportDeferredWork(
            pendingSupertypeEdges: [],
            importedBindings: [],
            lazyLoaderState: DataFlowSemaPhase.ImportedLibraryLazyLoaderState(),
            stdlibModuleName: interner.intern("stdlib"),
            klibModules: [],
            stdlibMemberKeys: []
        )

        KklibSemaSession.isEnabled = true
        defer { KklibSemaSession.isEnabled = false }
        #expect(KklibSemaSession.shouldCache(options: options))
        KklibSemaSession.store(
            options: options,
            symbols: symbols,
            types: types,
            interner: interner,
            work: importWork,
            importDiagnostics: []
        )

        let snapshot = try #require(KklibSemaSession.cachedSnapshot(options: options))
        let firstSymbols = snapshot.makeSymbols()
        let firstTypes = snapshot.makeTypes(symbols: firstSymbols)
        let firstInterner = snapshot.interner.makeSemaWorkerInterner()
        let (inlineFunctions, restoredWork) = snapshot.makeDeferredWork(
            phase: DataFlowSemaPhase(),
            symbols: firstSymbols,
            types: firstTypes,
            diagnostics: DiagnosticEngine(),
            interner: firstInterner
        )
        #expect(firstSymbols.lookupAll(fqName: [firstInterner.intern("kotlin"), importedName]) == [importedSymbol])
        #expect(restoredWork.importedBindings.isEmpty)
        #expect(inlineFunctions.isEmpty)

        let requestOnlyName = firstInterner.intern("requestOnlyDeclaration")
        _ = firstSymbols.define(
            kind: .function,
            name: requestOnlyName,
            fqName: [requestOnlyName],
            declSite: nil,
            visibility: .public
        )

        let secondSymbols = snapshot.makeSymbols()
        let secondInterner = snapshot.interner.makeSemaWorkerInterner()
        #expect(secondSymbols.lookupAll(fqName: [secondInterner.intern("requestOnlyDeclaration")]).isEmpty)
        #expect(secondSymbols.lookupAll(fqName: [secondInterner.intern("kotlin"), importedName]) == [importedSymbol])
    }
}
