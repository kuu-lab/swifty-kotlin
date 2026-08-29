#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LibraryMetadataImportIntegrationTests {
    @Test
    func testSemaLoadsSymbolsFromKklibSearchPath() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)

                let sema = try #require(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(importedPlus != nil)
                #expect(!appCtx.diagnostics.hasError, "Unexpected errors: \(appCtx.diagnostics.diagnostics.map(\.message).joined(separator: "\n"))")
                let appFileDiagnostics = appCtx.diagnostics.diagnostics.filter { diag in
                    guard let range = diag.primaryRange else { return false }
                    return appCtx.sourceManager.path(of: range.start.file) == appPath
                }
                #expect(!appFileDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    @Test
    func testInlineLoweringExpandsImportedInlineFunctionFromKklib() throws {
        let librarySource = """
        package extdemo
        inline fun plus1(v: Int) = v + 1
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.plus1
            fun main() = plus1(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let sema = try #require(appCtx.sema)
                let importedInline = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus1" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.inlineFunction)
                }
                #expect(importedInline != nil)
                #expect(!sema.importedInlineFunctions.isEmpty)

                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )

                let calls = extractCallees(from: mainFunction.body, interner: appCtx.interner)
                #expect(!calls.contains("plus1"))
                #expect(calls.contains("kk_op_add"))
            }
        }
    }

    // KSP-472: インライン展開された本体がライブラリ側のプロパティ getter を呼ぶ場合、
    // getter は consumer の symbol table に外部リンク名付きで復元されないため、
    // 宣言名のままだとリンク時に undefined reference になる。mangle 済みリンク名へ
    // フォールバックすることを固定する。
    @Test
    func testImportedInlineBodyCallsLibraryPropertyGetterByLinkName() throws {
        let librarySource = """
        package extdemo
        val Int.doubled: Int
            get() = this * 2
        inline fun callDoubled(v: Int) = v.doubled
        """
        try withCompiledLibrary(source: librarySource, moduleName: "ExtDemo") { libraryPath in
            let appSource = """
            import extdemo.callDoubled
            fun main() = callDoubled(21)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)

                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )
                let calls = extractCallees(from: mainFunction.body, interner: appCtx.interner)
                #expect(
                    !calls.contains("doubled"),
                    "Inlined body must not call the getter by its declared name: \(calls)"
                )
                #expect(
                    calls.contains { $0.hasPrefix("kk_fn_get_") },
                    "Inlined body must call the library's mangled getter link name: \(calls)"
                )
            }
        }
    }

    @Test
    func testSemaSynthesizesNominalLayoutsAndLibraryMetadataContainsLayoutFields() throws {
        let source = """
        package layoutdemo
        class Base
        class Derived: Base
        """

        try withTemporaryFile(contents: source) { path in
            let semaCtx = makeCompilationContext(inputs: [path], moduleName: "LayoutSema", emit: .kirDump)
            try runToKIR(semaCtx)

            let sema = try #require(semaCtx.sema)
            let base = try #require(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Base" && symbol.kind == .class
            }))
            let derived = try #require(sema.symbols.allSymbols().first(where: { symbol in
                semaCtx.interner.resolve(symbol.name) == "Derived" && symbol.kind == .class
            }))

            let baseLayout = sema.symbols.nominalLayout(for: base.id)
            let derivedLayout = sema.symbols.nominalLayout(for: derived.id)
            #expect(baseLayout != nil)
            #expect(derivedLayout != nil)
            #expect(baseLayout?.objectHeaderWords == 2)
            #expect((baseLayout?.instanceSizeWords ?? 0) >= 2)
            #expect(derivedLayout?.superClass == base.id)
        }

        try withCompiledLibrary(source: source, moduleName: "LayoutLib") { libraryPath in
            let metadata = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            #expect(metadata.contains("layoutWords="))
            #expect(metadata.contains("vtable="))
            #expect(metadata.contains("itable="))
            #expect(metadata.contains("superFq=layoutdemo.Base"))
        }
    }

    @Test
    func testSemaAllocatesVtableSlotsFromImportedNominalMetadata() throws {
        let metadata = """
        symbols=2
        class _ fq=ext.C schema=v1
        function _ fq=ext.C.m schema=v1 arity=0 suspend=0
        """
        try withKklibFixture(moduleName: "ExtMeta", metadata: metadata) { libDirPath in
            let source = "fun main() = 0"
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "VTableImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let classSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    ctx.interner.resolve(symbol.name) == "C" && symbol.kind == .class
                }))
                let layout = sema.symbols.nominalLayout(for: classSymbol.id)
                #expect(layout != nil)
                #expect(layout?.vtableSlots.count == 1)
                #expect(layout?.vtableSize == 1)
                #expect(layout?.itableSlots.count == 0)
                #expect(layout?.itableSize == 0)
            }
        }
    }

    @Test
    func testSemaReusesVtableSlotForImportedOverrideMethods() throws {
        let metadata = """
        symbols=4
        class _ fq=ext.Base schema=v1 fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Base.m schema=v1 arity=0 suspend=0
        class _ fq=ext.Derived schema=v1 superFq=ext.Base fields=0 layoutWords=3 vtable=1 itable=0
        function _ fq=ext.Derived.m schema=v1 arity=0 suspend=0
        """
        try withKklibFixture(moduleName: "ExtMetaOverride", metadata: metadata) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "VTableOverrideImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let baseClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
                let derivedClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived")]).first)
                let baseMethod = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base"), ctx.interner.intern("m")]).first)
                let derivedMethod = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Derived"), ctx.interner.intern("m")]).first)

                let baseLayout = try #require(sema.symbols.nominalLayout(for: baseClass))
                let derivedLayout = try #require(sema.symbols.nominalLayout(for: derivedClass))
                #expect(derivedLayout.superClass == baseClass)
                #expect(baseLayout.vtableSize == 1)
                #expect(derivedLayout.vtableSize == 1)
                #expect(derivedLayout.vtableSlots[baseMethod] == derivedLayout.vtableSlots[derivedMethod])
            }
        }
    }

    @Test
    func testSemaInheritsImportedFieldLayoutFromMetadataHints() throws {
        let metadata = """
        symbols=1
        class _ fq=ext.Base schema=v1 fields=1 layoutWords=4 vtable=0 itable=0
        """
        try withKklibFixture(moduleName: "ExtLayoutHint", metadata: metadata) { libDirPath in
            let source = """
            class Derived: ext.Base
            fun main() = 0
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "LayoutHintImport",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runToKIR(ctx)

                let sema = try #require(ctx.sema)
                let baseClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("ext"), ctx.interner.intern("Base")]).first)
                let derivedClass = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("Derived")]).first)
                let baseLayout = try #require(sema.symbols.nominalLayout(for: baseClass))
                let derivedLayout = try #require(sema.symbols.nominalLayout(for: derivedClass))

                #expect(baseLayout.instanceFieldCount == 1)
                #expect(baseLayout.instanceSizeWords == 4)
                #expect(derivedLayout.superClass == baseClass)
                #expect(derivedLayout.instanceFieldCount == 1)
                #expect(derivedLayout.instanceSizeWords == 4)
            }
        }
    }

    @Test
    func testLibraryMetadataExportsTypeSignatures() throws {
        let source = """
        package metaexport
        fun id(v: Int): Int = v
        val answer: Int = 42
        """
        try withCompiledLibrary(source: source, moduleName: "MetaExport") { libraryPath in
            let metadata = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            #expect(metadata.contains("function "))
            #expect(metadata.contains("property "))
            #expect(metadata.contains("sig=F1<I,I>"))
            #expect(metadata.contains("sig=I"))
        }
    }

    @Test
    func testImportedGenericClassResolvesExplicitTypeArgumentsAndMembers() throws {
        let source = """
        package genericlib
        class Holder<T> {
            fun wrap(value: T): T = value
        }
        """
        try withCompiledLibrary(source: source, moduleName: "GenericLib") { libraryPath in
            let metadata = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            #expect(metadata.contains("typeParams="))

            let appSource = """
            import genericlib.Holder
            fun main() {
                val holder = Holder<Int>()
                println(holder.wrap(1))
            }
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "GenericApp",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runToKIR(appCtx)

                #expect(
                    !appCtx.diagnostics.hasError,
                    "Unexpected errors: \(appCtx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: "\n"))"
                )

                let sema = try #require(appCtx.sema)
                let holder = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    appCtx.interner.resolve(symbol.name) == "Holder" && symbol.kind == .class
                }))
                #expect(sema.types.nominalTypeParameterSymbols(for: holder.id).count == 1)
            }
        }
    }

    @Test
    func testLibraryMetadataRoundTripsContextFunctionTypeSignatures() throws {
        let source = """
        package metaexport
        class A
        class B
        class C
        class D
        typealias Handler = context(A, B) C.() -> D
        val handler: Handler? = null
        """
        try withCompiledLibrary(source: source, moduleName: "MetaExportContext") { libraryPath in
            let metadata = try String(contentsOfFile: libraryPath + "/metadata.bin", encoding: .utf8)
            #expect(metadata.contains("typeAlias "))
            #expect(metadata.contains("fq=metaexport.Handler"))
            #expect(metadata.contains("sig=Q<Lmetaexport.Handler;>"))
            #expect(metadata.contains("fq=metaexport.handler"))

            let appSource = """
            import metaexport.handler
            fun use(): Any? = handler
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let importCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "MetaExportContextImport",
                    emit: .kirDump,
                    searchPaths: [libraryPath]
                )
                try runSema(importCtx)

                let sema = try #require(importCtx.sema)
                let handlerProperty = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    importCtx.interner.resolve(symbol.name) == "handler" &&
                        symbol.kind == .property &&
                        symbol.flags.contains(.synthetic)
                }))
                let propertyType = try #require(sema.symbols.propertyType(for: handlerProperty.id))
                let nonNullPropertyType = sema.types.makeNonNullable(propertyType)
                switch sema.types.kind(of: nonNullPropertyType) {
                case .any(.nonNull):
                    #expect(sema.types.renderType(nonNullPropertyType).contains("Any"))
                case let .functionType(functionType):
                    #expect(functionType.contextReceivers.count == 2)
                    #expect(functionType.receiver != nil)
                default:
                    Issue.record("Expected imported handler to be Any or a context-receiver function type, got \(sema.types.renderType(nonNullPropertyType))")
                }
            }
        }
    }

    @Test
    func testPlatformWarningEmittedForImportedMissingSignatureInExplicitNonNullContext() throws {
        let metadata = """
        symbols=1
        function _ fq=ext.platformValue schema=v1 arity=0 suspend=0
        """
        try withKklibFixture(moduleName: "ExtPlatformWarn", metadata: metadata) { libDirPath in
            let source = """
            import ext.platformValue

            fun useExplicit(): Any {
                val x: Any = platformValue()
                return x
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformWarn",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-PLATFORM" }
                #expect(
                    !warnings.isEmpty,
                    "Expected KSWIFTK-SEMA-PLATFORM, got: \(ctx.diagnostics.diagnostics.map(\.code))"
                )
                #expect(warnings.allSatisfy { $0.primaryRange != nil })
            }
        }
    }

    @Test
    func testPlatformWarningSuppressedForInferredReturnTypeFromImportedMissingSignature() throws {
        let metadata = """
        symbols=1
        function _ fq=ext.platformValue schema=v1 arity=0 suspend=0
        """
        try withKklibFixture(moduleName: "ExtPlatformSuppressed", metadata: metadata) { libDirPath in
            let source = """
            import ext.platformValue

            fun inferred() = platformValue()
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformWarnSuppressed",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-PLATFORM", in: ctx)
            }
        }
    }

    @Test
    func testPlatformValueAssignsToExplicitNullableContextWithoutWarning() throws {
        let metadata = """
        symbols=1
        function _ fq=ext.platformValue schema=v1 arity=0 suspend=0
        """
        try withKklibFixture(moduleName: "ExtPlatformNullable", metadata: metadata) { libDirPath in
            let source = """
            import ext.platformValue

            fun useNullable(): Any? {
                val x: Any? = platformValue()
                return x
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "PlatformNullable",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-PLATFORM", in: ctx)
                #expect(!ctx.diagnostics.hasError)
            }
        }
    }

    /// Regression: when metadata provides Collection.contains, listOf(...).contains must not emit VAR-OUT.
    /// Verifies metadata import and synthetic stub interaction for variance relaxation.
    @Test
    func testMetadataCollectionContainsDoesNotCauseVarOutWithListOf() throws {
        let metadata = """
        symbols=2
        interface _ fq=kotlin.collections.Collection schema=v1
        function _ fq=kotlin.collections.Collection.contains schema=v1 arity=1 suspend=0
        """
        try withKklibFixture(moduleName: "ExtCollectionMeta", metadata: metadata) { libDirPath in
            let source = """
            fun main() {
                val list = listOf(1, 2, 3)
                list.contains(2)
                list.isEmpty()
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "CollectionMetaApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
                #expect(!ctx.diagnostics.hasError)
            }
        }
    }
}
#endif
