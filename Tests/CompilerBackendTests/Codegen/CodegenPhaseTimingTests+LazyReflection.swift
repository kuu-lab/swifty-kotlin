@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension CodegenPhaseTimingTests {
    @Test
    func reflectionProjectionOmitsRecordsAlreadyEmbeddedByImportedArtifacts() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        let interner = StringInterner()
        let name = interner.intern("ArtifactType")
        _ = symbols.define(
            kind: .class,
            name: name,
            fqName: [interner.intern("library"), name],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary, .precomputedRuntimeReflection]
        )
        let encoder = MetadataEncoder()
        let projected = encoder.buildRecords(
            symbols: symbols,
            types: types,
            moduleName: "Consumer",
            interner: interner,
            functionLinkNames: [:],
            runtimeReflectionOnly: true
        )
        let complete = encoder.buildRecords(
            symbols: symbols,
            types: types,
            moduleName: "Consumer",
            interner: interner,
            functionLinkNames: [:]
        )
        #expect(!projected.contains { $0.fqName == "library.ArtifactType" })
        #expect(complete.contains { $0.fqName == "library.ArtifactType" })
    }

    @Test func reflectionUsesUpdatedSignaturesAndLegacyFallback() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        let interner = StringInterner()
        func define(_ name: String) -> SymbolID {
            symbols.define(
                kind: .function, name: interner.intern(name), fqName: [interner.intern(name)],
                declSite: nil, visibility: .public, flags: [.importedLibrary, .suspendFunction]
            )
        }
        let indexed = define("indexed")
        let updated = define("updated")
        let legacy = define("legacy")
        for id in [indexed, updated] {
            symbols.setImportedMemberIndexShape(ImportedMemberIndexShape(arity: 2, receiverOwnerFQName: nil), for: id)
        }
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: types.intType), for: updated)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader(alreadyLoaded: [updated]) { id in
            loaded.append(id)
            symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: types.intType), for: id)
        }
        // Test the projection itself separately from visibility selection.
        let encoder = MetadataEncoder()
        let projected = [indexed, updated, legacy].map { id in
            encoder.buildRuntimeReflectionRecord(
                for: symbols.symbol(id)!, symbols: symbols, interner: interner,
                inlineFunctionSymbols: [indexed, updated, legacy]
            )
        }
        #expect(projected.map(\.arity) == [2, 1, 1])
        #expect(projected.map(\.isSuspend) == [true, false, false])
        #expect(projected.allSatisfy { $0.isInline })
        #expect(loaded == [legacy])
    }

    @Test(arguments: [false, true], [false, true])
    func indexedReflectionPreservesBytesWithoutLoadingCallables(includeNonPublic: Bool, legacy: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = [
            MetadataRecord(kind: .class, mangledName: "_owner", fqName: "lazy.Owner", arity: 0, isSuspend: false),
            MetadataRecord(kind: .class, visibility: .internal, mangledName: "_hidden", fqName: "lazy.Hidden", arity: 0, isSuspend: false),
            MetadataRecord(kind: .function, mangledName: "_suspend", fqName: "lazy.Owner.suspended", arity: 2, isSuspend: true, typeSignature: "SF2<I,I,I>"),
            MetadataRecord(kind: .function, mangledName: "_overload1", fqName: "lazy.overloaded", arity: 1, isSuspend: false, typeSignature: "F1<I,I>"),
            MetadataRecord(kind: .function, mangledName: "_overload2", fqName: "lazy.overloaded", arity: 2, isSuspend: false, typeSignature: "F2<I,I,I>"),
            MetadataRecord(kind: .constructor, mangledName: "_ctor", fqName: "lazy.Owner.<init>", arity: 1, isSuspend: false, typeSignature: "F1<I,Llazy.Owner;>"),
            MetadataRecord(kind: .function, mangledName: "_hiddenMember", fqName: "lazy.Hidden.member", arity: 1, isSuspend: false, typeSignature: "F1<I,I>"),
            MetadataRecord(kind: .function, visibility: .private, mangledName: "_private", fqName: "lazy.secret", arity: 0, isSuspend: false, typeSignature: "F0<I>"),
        ]
        let encoder = MetadataEncoder()
        try "{\"formatVersion\":1,\"moduleName\":\"Lazy\",\"metadata\":\"metadata.bin\"}".write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try (legacy ? encoder.serialize(records) : encoder.serializeIndexed(records)).write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let symbols = SymbolTable()
        let types = TypeSystem()
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: CompilerOptions(
                moduleName: "Consumer", inputs: [], outputPath: "unused", emit: .llvmIR,
                searchPaths: [directory.path], target: .hostDefault(), includeStdlib: false
            ),
            symbols: symbols, types: types, diagnostics: diagnostics, interner: interner,
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        // Nominals are required by layout synthesis independently of reflection.
        for binding in work.importedBindings where binding.record.kind == .class {
            _ = symbols.nominalLayout(for: binding.symbol)
        }
        let callables = work.importedBindings.filter { $0.record.kind == .function || $0.record.kind == .constructor }
        #expect(callables.allSatisfy { $0.isMaterialized == legacy })
        let projected = encoder.buildRecords(
            symbols: symbols, types: types, moduleName: "Consumer", interner: interner,
            functionLinkNames: [:], includeNonPublic: includeNonPublic, runtimeReflectionOnly: true
        )
        #expect(callables.allSatisfy { $0.isMaterialized == legacy })
        if !legacy {
            // KUU-2675: pending compact-index shells are not reachable from
            // the compiled program, so the runtime projection omits them
            // instead of decoding their bodies. Nominals whose layouts were
            // materialized above still project from shell state.
            #expect(!projected.contains { $0.kind == .function || $0.kind == .constructor })
            #expect(projected.contains { $0.fqName == "lazy.Owner" && $0.kind == .class })
            #expect(projected.contains { $0.fqName == "lazy.Hidden" } == includeNonPublic)
            // Symbols whose bodies a semantic query did materialize regain
            // their record — reachability is tracked by load state, not by
            // how the symbol was imported.
            for binding in callables {
                symbols.ensureLazyImportedMetadataLoaded(for: binding.symbol)
            }
        }
        let loadedProjected = encoder.buildRecords(
            symbols: symbols, types: types, moduleName: "Consumer", interner: interner,
            functionLinkNames: [:], includeNonPublic: includeNonPublic, runtimeReflectionOnly: true
        )
        #expect(loadedProjected.contains { $0.fqName == "lazy.Owner.suspended" && $0.arity == 2 && $0.isSuspend })
        #expect(loadedProjected.filter { $0.fqName == "lazy.overloaded" }.map(\.arity).sorted() == [1, 2])
        #expect(loadedProjected.contains { $0.kind == .constructor && $0.arity == 1 })
        #expect(loadedProjected.contains { $0.fqName == "lazy.Hidden.member" } == includeNonPublic)
        #expect(loadedProjected.contains { $0.fqName == "lazy.secret" } == includeNonPublic)
        let full = encoder.buildRecords(
            symbols: symbols, types: types, moduleName: "Consumer", interner: interner,
            functionLinkNames: [:], includeNonPublic: includeNonPublic
        )
        #expect(RuntimeReflectionMetadataEmitter.serialize(loadedProjected) == RuntimeReflectionMetadataEmitter.serialize(full))
        #expect(!diagnostics.hasError)
    }
}
