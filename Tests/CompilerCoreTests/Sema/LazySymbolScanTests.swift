@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LazySymbolScanTests {
    @Test func knownMetadataQueriesDoNotInvokeLoader() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let owner = symbols.define(kind: .class, name: interner.intern("Owner"), fqName: [interner.intern("Owner")], declSite: nil, visibility: .public)
        let child = symbols.define(kind: .function, name: interner.intern("member"), fqName: [interner.intern("Owner"), interner.intern("member")], declSite: nil, visibility: .public, flags: [.importedLibrary])
        symbols.setParentSymbol(owner, for: child)
        symbols.setExternalLinkName("owner_member", for: child)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { symbol in
            loaded.append(symbol)
            symbols.setFunctionSignature(FunctionSignature(parameterTypes: [], returnType: types.intType), for: symbol)
        }
        #expect(symbols.parentSymbolIfKnown(for: child) == owner)
        #expect(symbols.children(of: owner) == [child])
        #expect(symbols.externalLinkNameIfKnown(for: child) == "owner_member")
        #expect(symbols.functionSignatureIfKnown(for: child) == nil)
        #expect(loaded.isEmpty)
        #expect(symbols.functionSignature(for: child)?.returnType == types.intType)
        #expect(symbols.functionSignatureIfKnown(for: child)?.returnType == types.intType)
        #expect(symbols.parentSymbol(for: child) == owner)
        #expect(loaded == [child])
    }

    @Test func childrenIndexTracksReparentingAndRepeatedRegistration() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        func define(_ name: String, kind: SymbolKind) -> SymbolID {
            symbols.define(kind: kind, name: interner.intern(name), fqName: [interner.intern(name)], declSite: nil, visibility: .public)
        }
        let firstOwner = define("First", kind: .class)
        let secondOwner = define("Second", kind: .class)
        let firstChild = define("first", kind: .function)
        let secondChild = define("second", kind: .function)
        symbols.setParentSymbol(firstOwner, for: secondChild)
        symbols.setParentSymbol(firstOwner, for: firstChild)
        symbols.setParentSymbol(firstOwner, for: firstChild)
        #expect(symbols.children(of: firstOwner) == [firstChild, secondChild])
        symbols.setParentSymbol(secondOwner, for: firstChild)
        #expect(symbols.children(of: firstOwner) == [secondChild])
        #expect(symbols.children(of: secondOwner) == [firstChild])
        #expect(symbols.parentSymbolIfKnown(for: firstChild) == secondOwner)
    }

    @Test(arguments: ["v2", "old-v2", "v3"])
    func indexedImportsAndLoweringKeepUnusedShellsLazy(format: String) throws {
        let oldInitializerIndex = format == "old-v2"
        let compact = format == "v3"
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: libDir) }
        let records = [
            // Put members before their owner to exercise late owner registration.
            MetadataRecord(kind: .function, mangledName: "_member", fqName: "scan.Owner.member", arity: 0, isSuspend: false, typeSignature: "F0<I>", externalLinkName: "scan_member"),
            MetadataRecord(kind: .property, mangledName: "_value", fqName: "scan.Owner.value", arity: 0, isSuspend: false, typeSignature: "I"),
            MetadataRecord(kind: .function, mangledName: "_extension", fqName: "scan.extension", arity: 0, isSuspend: false, receiverOwnerFQName: "scan.Owner", typeSignature: "F0<RLscan.Owner;,I>"),
            MetadataRecord(kind: .function, mangledName: "_member_extension", fqName: "scan.Owner.memberExtension", arity: 0, isSuspend: false, isMemberExtension: true, receiverOwnerFQName: "scan.Other", typeSignature: "F0<RLscan.Other;,I>"),
            MetadataRecord(kind: .class, mangledName: "_nested", fqName: "scan.Owner.Nested", arity: 0, isSuspend: false),
            MetadataRecord(kind: .class, mangledName: "_other", fqName: "scan.Other", arity: 0, isSuspend: false),
            MetadataRecord(kind: .class, mangledName: "_owner", fqName: "scan.Owner", arity: 0, isSuspend: false),
            MetadataRecord(kind: .object, mangledName: "_singleton", fqName: "scan.Singleton", arity: 0, isSuspend: false, objectInitializerLinkName: "scan_object_init"),
        ]
        var metadata = MetadataEncoder().serializeIndexed(records)
        if oldInitializerIndex {
            let sections = metadata.components(separatedBy: "\nbody\n")
            let oldIndex = sections[0]
                .replacingOccurrences(of: " initIndex=1", with: "")
                .replacingOccurrences(of: " objectInitLink=scan_object_init", with: "")
            metadata = oldIndex + "\nbody\n" + sections[1]
        }
        try "{\"formatVersion\":\(compact ? 2 : 1),\"moduleName\":\"Scan\",\"metadata\":\"metadata.bin\"}".write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let data = compact ? MetadataEncoder().serializeCompactIndexed(records) : Data(metadata.utf8)
        try data.write(to: libDir.appendingPathComponent("metadata.bin"))

        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [libDir.path], includeStdlib: false)
            // Bind source before importing to isolate these scans from KUU-1955.
            try runFrontend(ctx)
            let sourceContext = makeCompilationContext(inputs: [path], includeStdlib: false, interner: ctx.interner)
            try runSema(sourceContext)
            let sema = try #require(sourceContext.sema)
            ctx.storeSema(sema)
            let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: sema.symbols, types: sema.types,
                diagnostics: ctx.diagnostics, interner: ctx.interner,
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            let symbols = sema.symbols
            func id(_ fqName: String) throws -> SymbolID {
                try #require(symbols.lookup(fqName: fqName.split(separator: ".").map { ctx.interner.intern(String($0)) }))
            }
            let owner = try id("scan.Owner")
            let member = try id("scan.Owner.member")
            let property = try id("scan.Owner.value")
            let ext = try id("scan.extension")
            let memberExtension = try id("scan.Owner.memberExtension")
            let nested = try id("scan.Owner.Nested")
            #expect(symbols.parentSymbolIfKnown(for: member) == owner)
            #expect(symbols.parentSymbolIfKnown(for: property) == owner)
            #expect(symbols.parentSymbolIfKnown(for: ext) == owner)
            #expect(symbols.parentSymbolIfKnown(for: memberExtension) == owner)
            #expect(symbols.parentSymbolIfKnown(for: nested) == owner)
            #expect(symbols.children(of: owner) == [member, property, ext, memberExtension, nested])
            #expect(symbols.externalLinkNameIfKnown(for: member) == "scan_member")
            #expect(symbols.functionSignatureIfKnown(for: member) == nil)
            #expect(symbols.mayHaveImportedInitializers(for: owner) == oldInitializerIndex)
            _ = TypeCheckScopeBuilder().collectLibraryTopLevelSymbolsByPackage(sema: sema, interner: ctx.interner)
            #expect(work.importedBindings.allSatisfy { !$0.isMaterialized })

            try BuildKIRPhase().run(ctx)
            let module = try #require(ctx.kir)
            let passContext = makeKIRContext(from: ctx)
            try PropertyLoweringPass().run(module: module, ctx: passContext)
            try ABILoweringPass().run(module: module, ctx: passContext)
            for binding in work.importedBindings where [member, property, ext, memberExtension].contains(binding.symbol) {
                #expect(!binding.isMaterialized)
            }
            let ownerBinding = try #require(work.importedBindings.first { $0.symbol == owner })
            #expect(ownerBinding.isMaterialized == oldInitializerIndex)
            let initializerCalls = module.arena.declarations.compactMap { $0.function }.flatMap(\.body).contains {
                guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
                return ctx.interner.resolve(callee) == "scan_object_init"
            }
            #expect(initializerCalls)
            #expect(!ctx.diagnostics.hasError)
        }
    }

    @Test func compactIndexRetainsAllEagerInitializerLinks() throws {
        let record = MetadataRecord(
            kind: .enumClass, mangledName: "_enum", fqName: "scan.Enum",
            arity: 0, isSuspend: false, objectInitializerLinkName: "object_init",
            companionInitializerLinkName: "companion_init", enumStaticInitLinkName: "enum_init"
        )
        let indexed = try #require(IndexedMetadataFile(data: Data(MetadataEncoder().serializeIndexed([record]).utf8)))
        let entry = try #require(indexed.entries.first)
        #expect(entry.hasCompleteInitializerInfo)
        #expect(entry.record.objectInitializerLinkName == "object_init")
        #expect(entry.record.companionInitializerLinkName == "companion_init")
        #expect(entry.record.enumStaticInitLinkName == "enum_init")
    }

    @Test func normalizeImportedNonGenericMemberDoesNotInvokeLazyLoader() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let ownerName = ["scan", "Owner"].map(interner.intern)
        let owner = symbols.define(
            kind: .class, name: ownerName.last!, fqName: ownerName,
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        let methodName = interner.intern("method")
        let methodFQName = ownerName + [methodName]
        let method = symbols.define(
            kind: .function, name: methodName, fqName: methodFQName,
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        symbols.setParentSymbol(owner, for: method)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.intType), for: method
        )
        let record = try #require(DataFlowSemaPhase().makeImportedLibraryRecord(
            MetadataRecord(
                kind: .function, mangledName: "_method", fqName: "scan.Owner.method",
                arity: 0, isSuspend: false, typeSignature: "F0<I>"
            ),
            path: "metadata.bin", diagnostics: DiagnosticEngine(), interner: interner,
            nominalTypeParametersByFQName: [:]
        ))
        let binding = DataFlowSemaPhase.ImportedLibraryBinding(
            record: record, symbol: method, metadataPath: "metadata.bin",
            inlineKIRDir: nil, isStdlibArtifact: false
        )
        let work = DataFlowSemaPhase.LibraryImportDeferredWork(
            pendingSupertypeEdges: [], importedBindings: [binding], lazyLoaderState: nil,
            stdlibModuleName: nil, klibModules: []
        )
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }

        DataFlowSemaPhase().normalizeImportedLibraryMemberSignatures(
            work, symbols: symbols, types: types, diagnostics: DiagnosticEngine(), interner: interner
        )

        #expect(loaded.isEmpty)
        #expect(symbols.functionSignatureIfKnown(for: method)?.returnType == types.intType)
    }

    @Test func parameterlessImportedOverridesDoNotMaterializeForDefaults() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let name = interner.intern("toString")
        let function = symbols.define(
            kind: .function, name: name, fqName: [name], declSite: nil,
            visibility: .public, flags: [.synthetic, .importedLibrary, .overrideMember]
        )
        symbols.setImportedMemberIndexShape(
            ImportedMemberIndexShape(arity: 0, receiverOwnerFQName: nil), for: function
        )
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }

        DataFlowSemaPhase().inheritDefaultArgumentValuesForOverrides(symbols: symbols, types: TypeSystem())

        #expect(loaded.isEmpty)
        #expect(symbols.functionSignatureIfKnown(for: function) == nil)
        #expect(symbols.overrideDefaultsBaseSymbol(for: function) == nil)
    }

    @Test func importedLayoutsStayLazyAndLateUseSynthesizesAncestors() throws {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        func nominal(_ name: String) -> SymbolID {
            let part = interner.intern(name)
            return symbols.define(
                kind: .class, name: part, fqName: [part], declSite: nil,
                visibility: .public, flags: [.synthetic, .importedLibrary]
            )
        }
        let base = nominal("Base")
        let derived = nominal("Derived")
        let unused = nominal("Unused")
        let fieldName = interner.intern("field")
        let field = symbols.define(
            kind: .field, name: fieldName, fqName: [interner.intern("Base"), fieldName],
            declSite: nil, visibility: .public
        )
        symbols.setParentSymbol(base, for: field)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader(indexedNominals: [base, derived, unused]) { symbol in
            loaded.append(symbol)
            if symbol == base {
                symbols.setNominalLayoutHint(
                    NominalLayoutHint(
                        declaredFieldCount: 1, declaredInstanceSizeWords: 9,
                        declaredVtableSize: 3, declaredItableSize: 2
                    ),
                    for: base
                )
            } else if symbol == derived {
                symbols.setDirectSupertypes([base], for: derived)
                #expect(symbols.nominalLayout(for: derived) == nil)
            }
        }

        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: symbols, types: types, interner: interner, diagnostics: diagnostics
        )
        #expect(loaded.isEmpty)
        let layout = try #require(symbols.nominalLayout(for: derived))
        #expect(layout.objectHeaderWords == 2)
        #expect(layout.instanceSizeWords == 9)
        #expect(layout.instanceFieldCount == 1)
        #expect(layout.fieldOffsets[field] == 2)
        #expect(layout.vtableSize == 3)
        #expect(layout.itableSize == 2)
        #expect(layout.superClass == base)
        #expect(loaded.filter { $0 == base || $0 == derived } == [derived, base])
        #expect(!loaded.contains(unused))
        let firstLoads = loaded
        #expect(symbols.nominalLayout(for: derived) == layout)
        #expect(loaded == firstLoads)
        #expect(!diagnostics.hasError)
    }

    /// KUU-2674: an indexed nominal an earlier pass already materialized must
    /// also stay out of the eager batch — under the pending-only filter it was
    /// still synthesized, decoding supertype shells nothing had used. The
    /// batch leaves pending and materialized compact-index nominals alike to
    /// the on-demand synthesizer behind `nominalLayout(for:)`.
    @Test func materializedIndexedLayoutsAreSkippedByInitialBatch() throws {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        func nominal(_ name: String) -> SymbolID {
            let part = interner.intern(name)
            return symbols.define(
                kind: .class, name: part, fqName: [part], declSite: nil,
                visibility: .public, flags: [.synthetic, .importedLibrary]
            )
        }
        let eager = nominal("Eager")
        let pending = nominal("Pending")
        let unused = nominal("Unused")
        symbols.setDirectSupertypes([pending], for: eager)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader(
            alreadyLoaded: [eager],
            indexedNominals: [eager, pending, unused],
            lazyShells: [pending, unused]
        ) { symbol in
            loaded.append(symbol)
        }

        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: symbols, types: types, interner: interner, diagnostics: diagnostics
        )
        // `eager` passed the old pending filter, so the batch walked its
        // supertypes and decoded `pending`; now the whole cone stays lazy.
        #expect(loaded.isEmpty)

        let layout = try #require(symbols.nominalLayout(for: eager))
        #expect(layout.superClass == pending)
        #expect(loaded == [pending])
        #expect(symbols.nominalLayout(for: pending) != nil)
        #expect(loaded == [pending])
        #expect(!diagnostics.hasError)
    }

    @Test func defaultArgumentScanLoadsDemandedBaseAndPreservesOriginalOwner() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let types = TypeSystem()
        func define(_ name: String, kind: SymbolKind, flags: SymbolFlags = []) -> SymbolID {
            let fqName = name.split(separator: ".").map { interner.intern(String($0)) }
            return symbols.define(kind: kind, name: fqName.last!, fqName: fqName, declSite: nil, visibility: .public, flags: flags)
        }
        let a = define("A", kind: .class)
        let b = define("B", kind: .class)
        let c = define("C", kind: .class)
        // Visit the most-derived override first to exercise deferred snapshots.
        let cFunction = define("C.f", kind: .function, flags: [.overrideMember])
        let bFunction = define("B.f", kind: .function, flags: [.overrideMember])
        let aFunction = define("A.f", kind: .function, flags: [.synthetic, .importedLibrary])
        let unused = define("unused", kind: .function, flags: [.synthetic, .importedLibrary])
        symbols.setParentSymbol(a, for: aFunction)
        symbols.setParentSymbol(b, for: bFunction)
        symbols.setParentSymbol(c, for: cFunction)
        symbols.setDirectSupertypes([a], for: b)
        symbols.setDirectSupertypes([b], for: c)
        for function in [bFunction, cFunction] {
            symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: types.intType, valueParameterHasDefaultValues: [false]), for: function)
        }
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader(alreadyLoaded: [a, b, c, bFunction, cFunction]) { symbol in
            loaded.append(symbol)
            if symbol == aFunction {
                symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: types.intType, valueParameterHasDefaultValues: [true]), for: symbol)
            }
        }
        DataFlowSemaPhase().inheritDefaultArgumentValuesForOverrides(symbols: symbols, types: types)
        for function in [bFunction, cFunction] {
            #expect(symbols.functionSignatureIfKnown(for: function)?.valueParameterHasDefaultValues == [true])
            #expect(symbols.overrideDefaultsBaseSymbol(for: function) == aFunction)
        }
        #expect(loaded == [aFunction])
        #expect(symbols.functionSignatureIfKnown(for: unused) == nil)
    }

    @Test func metadataExportFilteringDoesNotLoadExcludedImports() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        _ = symbols.define(kind: .function, name: interner.intern("unused"), fqName: [interner.intern("unused")], declSite: nil, visibility: .public, flags: [.synthetic, .importedLibrary])
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }
        let records = MetadataEncoder().buildRecords(
            symbols: symbols, types: TypeSystem(), moduleName: "Scan",
            interner: interner, functionLinkNames: [:], includeSynthetic: false
        )
        #expect(records.isEmpty)
        #expect(loaded.isEmpty)
    }

    @Test func metadataExportVisibilityDoesNotLoadPrivateImportedOwner() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let owner = symbols.define(
            kind: .class, name: interner.intern("Hidden"), fqName: [interner.intern("Hidden")],
            declSite: nil, visibility: .private, flags: [.importedLibrary]
        )
        let member = symbols.define(
            kind: .function, name: interner.intern("member"),
            fqName: [interner.intern("Hidden"), interner.intern("member")],
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        symbols.setParentSymbol(owner, for: member)
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }
        let records = MetadataEncoder().buildRecords(
            symbols: symbols, types: TypeSystem(), moduleName: "Scan",
            interner: interner, functionLinkNames: [:], includeSynthetic: false
        )
        #expect(records.isEmpty)
        #expect(loaded.isEmpty)
    }

    @Test func defaultArgumentScanDoesNotLoadUnrelatedFunctions() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let function = symbols.define(kind: .function, name: interner.intern("unused"), fqName: [interner.intern("unused")], declSite: nil, visibility: .public, flags: [.importedLibrary])
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }
        DataFlowSemaPhase().inheritDefaultArgumentValuesForOverrides(symbols: symbols, types: TypeSystem())
        #expect(symbols.functionSignatureIfKnown(for: function) == nil)
        #expect(loaded.isEmpty)
    }

    @Test func defaultArgumentScanDoesNotLoadImportedOverridesWithoutDefaults() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        let interner = StringInterner()
        let baseClass = symbols.define(kind: .class, name: interner.intern("Base"), fqName: [interner.intern("Base")], declSite: nil, visibility: .public, flags: [.importedLibrary])
        let subClass = symbols.define(kind: .class, name: interner.intern("Sub"), fqName: [interner.intern("Sub")], declSite: nil, visibility: .public, flags: [.importedLibrary])
        symbols.setDirectSupertypes([baseClass], for: subClass)

        let baseFn = symbols.define(kind: .function, name: interner.intern("foo"), fqName: [interner.intern("Base"), interner.intern("foo")], declSite: nil, visibility: .public, flags: [.importedLibrary])
        symbols.setParentSymbol(baseClass, for: baseFn)
        symbols.setImportedMemberIndexShape(ImportedMemberIndexShape(arity: 1, receiverOwnerFQName: nil, hasDefaultArguments: false), for: baseFn)

        let subFn = symbols.define(kind: .function, name: interner.intern("foo"), fqName: [interner.intern("Sub"), interner.intern("foo")], declSite: nil, visibility: .public, flags: [.overrideMember, .importedLibrary])
        symbols.setParentSymbol(subClass, for: subFn)
        symbols.setImportedMemberIndexShape(ImportedMemberIndexShape(arity: 1, receiverOwnerFQName: nil, hasDefaultArguments: false), for: subFn)

        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { symbol in
            loaded.append(symbol)
            if symbol == baseFn || symbol == subFn {
                symbols.setFunctionSignature(FunctionSignature(parameterTypes: [types.intType], returnType: types.unitType, valueParameterHasDefaultValues: [false]), for: symbol)
            }
        }

        DataFlowSemaPhase().inheritDefaultArgumentValuesForOverrides(symbols: symbols, types: types)
        #expect(loaded.isEmpty)
        #expect(symbols.functionSignatureIfKnown(for: baseFn) == nil)
        #expect(symbols.functionSignatureIfKnown(for: subFn) == nil)
    }

    /// Compact-index entries keep registering through provider drains after
    /// the lazy loader installs, so the install-time `lazyShells` snapshot
    /// misses them. They must still count as pending shells: the runtime
    /// reflection projection would otherwise decode every nominal the program
    /// never used, and member-existence checks would force the same decode.
    @Test func postInstallDrainedShellsStayPendingForReflectionAndDeferral() throws {
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: libDir) }
        let records = [
            MetadataRecord(kind: .function, mangledName: "_member", fqName: "scan.Owner.member", arity: 0, isSuspend: false, typeSignature: "F0<I>", externalLinkName: "scan_member"),
            MetadataRecord(kind: .class, mangledName: "_nested", fqName: "scan.Owner.Nested", arity: 0, isSuspend: false),
            MetadataRecord(kind: .class, mangledName: "_owner", fqName: "scan.Owner", arity: 0, isSuspend: false),
        ]
        try "{\"formatVersion\":2,\"moduleName\":\"Scan\",\"metadata\":\"metadata.bin\"}".write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try MetadataEncoder().serializeCompactIndexed(records).write(to: libDir.appendingPathComponent("metadata.bin"))

        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [libDir.path], includeStdlib: false)
            try runFrontend(ctx)
            let sourceContext = makeCompilationContext(inputs: [path], includeStdlib: false, interner: ctx.interner)
            try runSema(sourceContext)
            let sema = try #require(sourceContext.sema)
            ctx.storeSema(sema)
            let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: sema.symbols, types: sema.types,
                diagnostics: ctx.diagnostics, interner: ctx.interner,
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            let symbols = sema.symbols
            func id(_ fqName: String) throws -> SymbolID {
                try #require(symbols.lookup(fqName: fqName.split(separator: ".").map { ctx.interner.intern(String($0)) }))
            }
            // These shells register through provider drains now — after the
            // lazy loader's snapshot — and must still count as pending.
            let owner = try id("scan.Owner")
            let nested = try id("scan.Owner.Nested")
            #expect(symbols.hasPendingImportedMetadata(for: owner))
            #expect(symbols.hasPendingImportedMetadata(for: nested))
            #expect(symbols.isUnmaterializedImportedShell(owner))
            // The member entry has not even been looked up yet: the deferral
            // check drains the path before deciding, so the work queues
            // instead of forcing an eager signature decode.
            var deferredRan = false
            #expect(symbols.deferWorkUntilImportedMemberMaterializes(
                at: ["scan", "Owner", "member"].map { ctx.interner.intern($0) },
                work: { deferredRan = true }
            ))
            #expect(!deferredRan)
            let member = try id("scan.Owner.member")
            // The runtime projection omits pending shells and must not decode
            // their bodies while deciding.
            let projected = MetadataEncoder().buildRecords(
                symbols: symbols, types: sema.types, moduleName: "Consumer",
                interner: ctx.interner, functionLinkNames: [:],
                runtimeReflectionOnly: true
            )
            #expect(!projected.contains { $0.fqName == "scan.Owner" })
            #expect(!projected.contains { $0.fqName == "scan.Owner.Nested" })
            #expect(!projected.contains { $0.fqName == "scan.Owner.member" })
            let pendingSymbols = Set([owner, nested, member])
            for binding in work.importedBindings where pendingSymbols.contains(binding.symbol) {
                #expect(!binding.isMaterialized)
            }
            #expect(symbols.hasPendingImportedMetadata(for: owner))
            #expect(!ctx.diagnostics.hasError)
        }
    }
}

