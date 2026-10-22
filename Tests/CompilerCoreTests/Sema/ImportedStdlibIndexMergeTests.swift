@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedStdlibIndexMergeTests {
    @Test
    func precomputedStdlibSyntheticAnchorsRestoreTypeSystemLookups() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let fixedPaths = [
            ["kotlin", "Any"], ["kotlin", "Annotation"], ["kotlin", "Comparable"],
            ["kotlin", "CharSequence"], ["kotlin", "String"], ["kotlin", "Char"],
            ["kotlin", "reflect", "KCallable"], ["kotlin", "reflect", "KFunction"],
            ["kotlin", "reflect", "KClass"],
        ]
        let functionPaths = (0 ... 22).flatMap { arity in
            [
                ["kotlin", "Function", "Function\(arity)"],
                ["kotlin", "coroutines", "SuspendFunction\(arity)"],
            ]
        }
        var symbolsByPath: [[String]: SymbolID] = [:]
        for path in fixedPaths + functionPaths {
            let name = interner.intern(path.last!)
            let symbol = symbols.define(
                kind: .interface,
                name: name,
                fqName: path.map { interner.intern($0) },
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.markImportedStdlibSymbol(symbol)
            symbolsByPath[path] = symbol
        }

        #expect(DataFlowSemaPhase().restorePrecomputedStdlibSyntheticTypeSymbols(
            symbols: symbols,
            types: types,
            interner: interner
        ))
        #expect(types.anyClassSymbol == symbolsByPath[["kotlin", "Any"]])
        #expect(types.annotationInterfaceSymbol == symbolsByPath[["kotlin", "Annotation"]])
        #expect(types.comparableInterfaceSymbol == symbolsByPath[["kotlin", "Comparable"]])
        #expect(types.charSequenceInterfaceSymbol == symbolsByPath[["kotlin", "CharSequence"]])
        #expect(types.stringClassSymbol == symbolsByPath[["kotlin", "String"]])
        #expect(types.charClassSymbol == symbolsByPath[["kotlin", "Char"]])
        #expect(types.kCallableInterfaceSymbol == symbolsByPath[["kotlin", "reflect", "KCallable"]])
        #expect(types.kFunctionInterfaceSymbol == symbolsByPath[["kotlin", "reflect", "KFunction"]])
        #expect(types.kClassInterfaceSymbol == symbolsByPath[["kotlin", "reflect", "KClass"]])
        #expect(types.functionNInterfaceSymbols[22] == symbolsByPath[["kotlin", "Function", "Function22"]])
        #expect(types.suspendFunctionNInterfaceSymbols[22]
            == symbolsByPath[["kotlin", "coroutines", "SuspendFunction22"]])
    }

    @Test
    func precomputedMemberIndexPreservesMemberAndAliasLookups() throws {
        let interner = StringInterner()
        let records = [
            MetadataRecord(kind: .function, mangledName: "_map", fqName: "kotlin.collections.List.map", arity: 1),
            MetadataRecord(kind: .function, mangledName: "_first0", fqName: "kotlin.collections.List.first", arity: 0),
            MetadataRecord(kind: .function, mangledName: "_first1", fqName: "kotlin.collections.List.first", arity: 1),
            MetadataRecord(
                kind: .function,
                mangledName: "_extension",
                fqName: "kotlin.collections.extension",
                arity: 2,
                receiverOwnerFQName: "kotlin.collections.List"
            ),
            MetadataRecord(kind: .constructor, mangledName: "_ctor", fqName: "demo.Widget.<init>", arity: 2),
        ]
        let data = BundledDeclarationIndex.precomputedMemberIndexData(records: records, interner: interner)
        let decoded = try #require(PrecomputedBundledMemberIndex(data: data, interner: interner))
        var index = BundledDeclarationIndex.empty
        index.insertImportedStdlibSymbols(
            keys: [],
            interner: interner,
            precomputedMemberIndex: decoded
        )

        let list = ["kotlin", "collections", "List"].map { interner.intern($0) }
        let iterable = ["kotlin", "collections", "Iterable"].map { interner.intern($0) }
        #expect(index.contains(owner: list, name: interner.intern("map"), arity: 1))
        #expect(index.contains(owner: iterable, name: interner.intern("map"), arity: 1))
        #expect(index.contains(owner: iterable, name: interner.intern("extension"), arity: 2))
        #expect(index.contains(owner: list, name: interner.intern("first"), arity: 0))
        #expect(index.contains(owner: iterable, name: interner.intern("first"), arity: 1))
        #expect(!index.contains(owner: iterable, name: interner.intern("first"), arity: 0))
        #expect(index.contains(owner: [interner.intern("demo"), interner.intern("Widget")],
                               name: interner.intern("<init>"), arity: 2))
        #expect(index.contains(ownerFQName: list, name: interner.intern("map")))
        #expect(PrecomputedBundledMemberIndex(data: Data("invalid".utf8), interner: interner) == nil)
    }

    @Test(arguments: [false, true])
    func constructorKeysPreserveArityAndDeferIndexedSignatures(indexed: Bool) throws {
        let libDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libDir) }
        try """
        {"formatVersion":1,"moduleName":"ConstructorShapes","metadata":"metadata.bin"}
        """.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let records = [
            MetadataRecord(kind: .package, mangledName: "_", fqName: "demo"),
            MetadataRecord(kind: .class, mangledName: "_Widget", fqName: "demo.Widget"),
            MetadataRecord(kind: .constructor, mangledName: "_WidgetCtor", fqName: "demo.Widget.<init>",
                           arity: 2, typeSignature: "F2<I,I,U>", valueParameterHasDefaultValues: [true, false]),
        ]
        let encoder = MetadataEncoder()
        let metadata = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let ctx = makeCompilationContext(inputs: [], searchPaths: [libDir.path])
        let symbols = SymbolTable()
        let types = TypeSystem()
        let phase = DataFlowSemaPhase()
        let work = phase.loadImportedLibrarySymbols(
            options: ctx.options, symbols: symbols, types: types, diagnostics: ctx.diagnostics,
            interner: ctx.interner, importedInlineFunctions: ImportedInlineFunctionStore()
        )
        let binding = try #require(work.importedBindings.first { $0.record.kind == .constructor })
        if indexed {
            #expect(!binding.isMaterialized)
            #expect(symbols.importedMemberIndexShape(for: binding.symbol)?.arity == 2)
        }
        let owner = ["demo", "Widget"].map { ctx.interner.intern($0) }
        let name = ctx.interner.intern("<init>")
        let index = phase.mergeImportedStdlibSymbolsIntoBundledIndex(
            bundledIndex: .empty, stdlibModuleName: ctx.interner.intern("ConstructorShapes"),
            symbols: symbols, types: types, interner: ctx.interner
        )
        #expect(index.contains(owner: owner, name: name, arity: 2))
        if indexed { #expect(!binding.isMaterialized) }
        let signature = try #require(symbols.functionSignature(for: binding.symbol))
        #expect(signature.parameterTypes == [types.intType, types.intType])
        #expect(signature.valueParameterHasDefaultValues == [true, false])
        #expect(binding.isMaterialized)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test
    func nominalLookupRetriesMissesAfterLazyConstructorCreatesAReceiver() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let module = interner.intern("Stdlib")
        let package = ["kotlin", "collections"].map { interner.intern($0) }
        let receiverFQName = package + [interner.intern("LateReceiver")]
        func define(_ kind: SymbolKind, _ name: String) -> SymbolID {
            let name = interner.intern(name)
            let id = symbols.define(kind: kind, name: name, fqName: package + [name],
                                    declSite: nil, visibility: .public, flags: [.importedLibrary])
            return id
        }
        let before = define(.function, "before")
        let constructor = define(.constructor, "<init>")
        let after = define(.function, "after")
        // Module assignment can differ from definition order when an import
        // reuses existing symbols. The merge must retain the old scan order.
        for id in [after, before, constructor] {
            symbols.setModuleFQN(module, for: id)
        }
        for id in [before, after] {
            symbols.setImportedMemberIndexShape(
                ImportedMemberIndexShape(arity: 0, receiverOwnerFQName: receiverFQName), for: id
            )
        }
        var receiver: SymbolID?
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { id in
            loaded.append(id)
            if id == constructor {
                receiver = symbols.define(kind: .class, name: receiverFQName.last!, fqName: receiverFQName,
                                          declSite: nil, visibility: .public)
                symbols.setFunctionSignature(
                    FunctionSignature(parameterTypes: [], returnType: types.unitType), for: id
                )
            }
        }
        let index = DataFlowSemaPhase().mergeImportedStdlibSymbolsIntoBundledIndex(
            bundledIndex: .empty, stdlibModuleName: module,
            symbols: symbols, types: types, interner: interner
        )
        #expect(loaded == [constructor])
        symbols.setLazyImportedMetadataLoader(nil)
        #expect(receiver != nil)
        #expect(symbols.parentSymbol(for: before) == nil)
        #expect(symbols.parentSymbol(for: after) == receiver)
        #expect(index.contains(owner: receiverFQName, name: interner.intern("after"), arity: 0))
    }

    @Test(arguments: [SymbolKind.class, .interface, .object, .enumClass, .annotationClass])
    func lazyExtensionsKeepDispatchOwnersAndDoNotMaterialize(nominalKind: SymbolKind) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let module = interner.intern("Stdlib")
        func define(_ kind: SymbolKind, _ path: [String]) -> SymbolID {
            let fqName = path.map { interner.intern($0) }
            return symbols.define(kind: kind, name: fqName.last!, fqName: fqName,
                                  declSite: nil, visibility: .public, flags: [.importedLibrary])
        }
        let receiverPath = ["kotlin", "collections", "Receiver"]
        let dispatchPath = ["kotlin", "collections", "Dispatch"]
        // Package records can share a nominal's FQName. They must not win
        // receiver lookup or hide the declaring owner of a member extension.
        _ = define(.package, receiverPath)
        let receiver = define(nominalKind, receiverPath)
        _ = define(.package, dispatchPath)
        let dispatch = define(nominalKind, dispatchPath)
        let package = define(.package, ["kotlin", "collections"])
        let topLevel = define(.function, ["kotlin", "collections", "touch"])
        let member = define(.function, dispatchPath + ["touch"])
        let regular = define(.function, ["kotlin", "collections", "plain"])
        let missingReceiver = define(.function, ["kotlin", "collections", "missing"])
        let receiverFQName = receiverPath.map { interner.intern($0) }
        for id in [topLevel, member] {
            symbols.setModuleFQN(module, for: id)
            symbols.setImportedMemberIndexShape(
                ImportedMemberIndexShape(arity: 1, receiverOwnerFQName: receiverFQName), for: id
            )
        }
        symbols.setParentSymbol(package, for: topLevel)
        symbols.setParentSymbol(dispatch, for: member)
        symbols.setParentSymbol(package, for: regular)
        symbols.setParentSymbol(package, for: missingReceiver)
        symbols.setModuleFQN(module, for: regular)
        symbols.setModuleFQN(module, for: missingReceiver)
        symbols.setImportedMemberIndexShape(
            ImportedMemberIndexShape(arity: 0, receiverOwnerFQName: nil), for: regular
        )
        symbols.setImportedMemberIndexShape(
            ImportedMemberIndexShape(arity: 0, receiverOwnerFQName: [interner.intern("Absent")]),
            for: missingReceiver
        )
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }

        let index = DataFlowSemaPhase().mergeImportedStdlibSymbolsIntoBundledIndex(
            bundledIndex: .empty, stdlibModuleName: module,
            symbols: symbols, types: types, interner: interner
        )
        #expect(loaded.isEmpty)
        #expect(index.contains(owner: receiverFQName, name: interner.intern("touch"), arity: 1))
        #expect(index.contains(owner: [interner.intern("kotlin"), interner.intern("collections")],
                               name: interner.intern("plain"), arity: 0))
        // Parent queries themselves force metadata, so inspect them only
        // after proving the merge did not invoke the loader.
        symbols.setLazyImportedMetadataLoader(nil)
        #expect(symbols.parentSymbol(for: topLevel) == receiver)
        #expect(symbols.parentSymbol(for: member) == dispatch)
        #expect(symbols.parentSymbol(for: regular) == package)
        #expect(symbols.parentSymbol(for: missingReceiver) == package)
    }

    @Test
    func retainedOverlapsStillContributeKeysWithoutReparenting() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let module = interner.intern("Stdlib")
        let receiverFQName = ["kotlin", "collections", "Iterable"].map { interner.intern($0) }
        let receiver = symbols.define(kind: .interface, name: receiverFQName.last!, fqName: receiverFQName,
                                      declSite: nil, visibility: .public)
        let packageFQName = Array(receiverFQName.dropLast())
        let package = symbols.define(kind: .package, name: packageFQName.last!, fqName: packageFQName,
                                     declSite: nil, visibility: .public)
        var functions: [SymbolID] = []
        // Both overloads share the retained arity key.
        for _ in 0..<2 {
            let name = interner.intern("filter")
            let id = symbols.define(kind: .function, name: name, fqName: packageFQName + [name],
                                    declSite: nil, visibility: .public, flags: [.importedLibrary])
            symbols.setModuleFQN(module, for: id)
            symbols.setParentSymbol(package, for: id)
            symbols.setImportedMemberIndexShape(
                ImportedMemberIndexShape(arity: 1, receiverOwnerFQName: receiverFQName), for: id
            )
            functions.append(id)
        }
        var loaded: [SymbolID] = []
        symbols.setLazyImportedMetadataLoader { loaded.append($0) }
        let index = DataFlowSemaPhase().mergeImportedStdlibSymbolsIntoBundledIndex(
            bundledIndex: .empty, stdlibModuleName: module,
            symbols: symbols, types: types, interner: interner
        )
        #expect(loaded.isEmpty)
        #expect(index.contains(owner: receiverFQName, name: interner.intern("filter"), arity: 1))
        symbols.setLazyImportedMetadataLoader(nil)
        for id in functions {
            #expect(symbols.parentSymbol(for: id) == package)
            #expect(symbols.parentSymbol(for: id) != receiver)
        }
    }

    @Test
    func eagerMembersPreserveKeysAndExcludeOtherModulesAndLocalSymbols() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let module = interner.intern("Stdlib")
        let ownerFQName = ["kotlin", "collections", "List"].map { interner.intern($0) }
        let owner = symbols.define(kind: .interface, name: ownerFQName.last!, fqName: ownerFQName,
                                   declSite: nil, visibility: .public)
        let receiverType = types.make(.classType(ClassType(classSymbol: owner)))
        let existing = BundledMemberKey(ownerFQName: [], name: interner.intern("existing"), arity: 0)
        var expected: [BundledMemberKey] = [existing]
        var extensionID: SymbolID?
        for (kind, name) in [(SymbolKind.function, "touch"), (.property, "size"),
                             (.field, "field"), (.constructor, "<init>")] {
            let name = interner.intern(name)
            let id = symbols.define(kind: kind, name: name, fqName: ownerFQName + [name],
                                    declSite: nil, visibility: .public, flags: [.importedLibrary])
            symbols.setModuleFQN(module, for: id)
            symbols.setParentSymbol(owner, for: id)
            if kind == .function || kind == .constructor {
                symbols.setFunctionSignature(
                    FunctionSignature(parameterTypes: [types.intType], returnType: types.unitType), for: id
                )
            }
            expected.append(BundledMemberKey(ownerFQName: ownerFQName, name: name,
                                             arity: kind == .function || kind == .constructor ? 1 : 0))
        }
        for (name, imported, owningModule) in [("extension", true, module),
                                              ("foreign", true, interner.intern("Other")),
                                              ("local", false, module)] {
            let name = interner.intern(name)
            let id = symbols.define(kind: .function, name: name,
                                    fqName: Array(ownerFQName.dropLast()) + [name], declSite: nil,
                                    visibility: .public, flags: imported ? [.importedLibrary] : [])
            symbols.setModuleFQN(owningModule, for: id)
            symbols.setFunctionSignature(
                FunctionSignature(receiverType: receiverType, parameterTypes: [], returnType: types.unitType),
                for: id
            )
            if name == interner.intern("extension") {
                extensionID = id
                expected.append(BundledMemberKey(ownerFQName: ownerFQName, name: name, arity: 0))
            }
        }
        let index = DataFlowSemaPhase().mergeImportedStdlibSymbolsIntoBundledIndex(
            bundledIndex: BundledDeclarationIndex(keys: [existing], nominalFQNames: [ownerFQName]),
            stdlibModuleName: module, symbols: symbols, types: types, interner: interner
        )
        for key in expected { #expect(index.contains(key)) }
        #expect(index.containsNominal(fqName: ownerFQName))
        #expect(symbols.parentSymbol(for: extensionID!) == owner)
        #expect(!index.contains(owner: ownerFQName, name: interner.intern("foreign"), arity: 0))
        #expect(!index.contains(owner: ownerFQName, name: interner.intern("local"), arity: 0))
        #expect(index.contains(owner: ["kotlin", "collections", "Iterable"].map { interner.intern($0) },
                               name: interner.intern("touch"), arity: 1))
    }
}
