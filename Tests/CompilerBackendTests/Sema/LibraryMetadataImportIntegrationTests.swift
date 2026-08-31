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
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)

                let sema = try #require(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(importedPlus != nil)
                #expect(!(appCtx.diagnostics.hasError), "Unexpected errors: \(appCtx.diagnostics.diagnostics.map(\.message).joined(separator: "\n"))")
                let appFileDiagnostics = appCtx.diagnostics.diagnostics.filter { diag in
                    guard let range = diag.primaryRange else { return false }
                    return appCtx.sourceManager.path(of: range.start.file) == appPath
                }
                #expect(!(appFileDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" }))
            }
        }
    }

    @Test
    func testInlineLoweringExpandsImportedInlineFunctionFromKklib() throws {
        let librarySource = """
        package extdemo
        inline fun plus1(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus1
            fun main() = plus1(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
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
                #expect(!(sema.importedInlineFunctions.isEmpty))

                let kir = try #require(appCtx.kir)
                let mainFunction = try #require(
                    findAllKIRFunctions(in: kir).first { function in
                        appCtx.interner.resolve(function.name) == "main"
                    },
                    "Expected lowered main function"
                )

                let calls = mainFunction.body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return appCtx.interner.resolve(callee)
                }
                #expect(!(calls.contains("plus1")))
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
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.callDoubled
            fun main() = callDoubled(21)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
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
                let calls = mainFunction.body.compactMap { instruction -> String? in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return appCtx.interner.resolve(callee)
                }
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

            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libCtx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutLib",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadataText = try String(contentsOfFile: metadataPath, encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let derivedRecord = try #require(records.first { $0.fqName == "layoutdemo.Derived" })
            #expect(derivedRecord.declaredInstanceSizeWords != nil)
            #expect(derivedRecord.declaredVtableSize != nil)
            #expect(derivedRecord.declaredItableSize != nil)
            #expect(derivedRecord.superFQName == "layoutdemo.Base")
        }
    }

    @Test
    func testSemaAllocatesVtableSlotsFromImportedNominalMetadata() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMeta",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(kind: .class, mangledName: "_", fqName: "ext.C"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.C.m"),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
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

    @Test
    func testSemaReusesVtableSlotForImportedOverrideMethods() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtMetaOverride",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Base",
                declaredFieldCount: 0,
                declaredInstanceSizeWords: 3,
                declaredVtableSize: 1,
                declaredItableSize: 0
            ),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.Base.m"),
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Derived",
                declaredFieldCount: 0,
                declaredInstanceSizeWords: 3,
                declaredVtableSize: 1,
                declaredItableSize: 0,
                superFQName: "ext.Base"
            ),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.Derived.m"),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "VTableOverrideImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
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

    @Test
    func testSemaInheritsImportedFieldLayoutFromMetadataHints() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtLayoutHint",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(
                kind: .class,
                mangledName: "_",
                fqName: "ext.Base",
                declaredFieldCount: 1,
                declaredInstanceSizeWords: 4,
                declaredVtableSize: 0,
                declaredItableSize: 0
            ),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        class Derived: ext.Base
        fun main() = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LayoutHintImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
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

    @Test
    func testLibraryMetadataExportsTypeSignatures() throws {
        let source = """
        package metaexport
        fun id(v: Int): Int = v
        val answer: Int = 42
        """
        try withTemporaryFile(contents: source) { path in
            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MetaExport",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadataText = try String(contentsOfFile: metadataPath, encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let idRecord = try #require(records.first { $0.fqName == "metaexport.id" })
            let answerRecord = try #require(records.first { $0.fqName == "metaexport.answer" })
            #expect(idRecord.kind == .function)
            #expect(idRecord.typeSignature == "F1<I,I>")
            #expect(answerRecord.kind == .property)
            #expect(answerRecord.typeSignature == "I")
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
        try withTemporaryFile(contents: source) { path in
            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libCtx = makeCompilationContext(
                inputs: [path],
                moduleName: "GenericLib",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadataText = try String(contentsOfFile: metadataPath, encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let holderRecord = try #require(records.first { $0.fqName == "genericlib.Holder" })
            #expect(holderRecord.nominalTypeParameters != nil)

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
                    searchPaths: [libBase + ".kklib"]
                )
                try runToKIR(appCtx)

                let messages = appCtx.diagnostics.diagnostics
                    .filter { $0.severity == .error }
                    .map(\.message)
                    .joined(separator: "\n")
                #expect(!appCtx.diagnostics.hasError, "Unexpected errors: \(messages)")

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
        try withTemporaryFile(contents: source) { path in
            let libBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let emitCtx = makeCompilationContext(
                inputs: [path],
                moduleName: "MetaExportContext",
                emit: .library,
                outputPath: libBase
            )
            try runToKIR(emitCtx)
            try LoweringPhase().run(emitCtx)
            try CodegenPhase().run(emitCtx)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadataText = try String(contentsOfFile: metadataPath, encoding: .utf8)
            let records = MetadataDecoder().decode(metadataText)
            let handlerTypeAlias = try #require(records.first { $0.fqName == "metaexport.Handler" })
            let handlerProperty = try #require(records.first { $0.fqName == "metaexport.handler" })
            #expect(handlerTypeAlias.kind == .typeAlias)
            #expect(handlerProperty.typeSignature == "Q<Lmetaexport.Handler;>")

            let appSource = """
            import metaexport.handler
            fun use(): Any? = handler
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let importCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "MetaExportContextImport",
                    emit: .kirDump,
                    searchPaths: [libBase + ".kklib"]
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
                    let rendered = sema.types.renderType(nonNullPropertyType)
                    #expect(rendered.contains("Any"))
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
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtPlatformWarn",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

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
                searchPaths: [libDir.path]
            )
            try runSema(ctx)

            let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-PLATFORM" }
            #expect(
                !(warnings.isEmpty),
                "Expected KSWIFTK-SEMA-PLATFORM, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
            #expect(warnings.allSatisfy { $0.primaryRange != nil })
        }
    }

    @Test
    func testPlatformWarningSuppressedForInferredReturnTypeFromImportedMissingSignature() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtPlatformSuppressed",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import ext.platformValue

        fun inferred() = platformValue()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "PlatformWarnSuppressed",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-PLATFORM" },
                "Unexpected KSWIFTK-SEMA-PLATFORM, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
        }
    }

    @Test
    func testPlatformValueAssignsToExplicitNullableContextWithoutWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtPlatformNullable",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(kind: .function, mangledName: "_", fqName: "ext.platformValue"),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

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
                searchPaths: [libDir.path]
            )
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-PLATFORM" },
                "Unexpected KSWIFTK-SEMA-PLATFORM, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    /// Regression: when metadata provides Collection.contains, listOf(...).contains must not emit VAR-OUT.
    /// Verifies metadata import and synthetic stub interaction for variance relaxation.
    @Test
    func testMetadataCollectionContainsDoesNotCauseVarOutWithListOf() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtCollectionMeta",
          "metadata": "metadata.bin"
        }
        """
        let metadata = MetadataEncoder().serialize([
            MetadataRecord(kind: .interface, mangledName: "_", fqName: "kotlin.collections.Collection"),
            MetadataRecord(kind: .function, mangledName: "_", fqName: "kotlin.collections.Collection.contains", arity: 1),
        ])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

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
                searchPaths: [libDir.path]
            )
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-VAR-OUT" },
                "Unexpected KSWIFTK-SEMA-VAR-OUT, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )
            #expect(!(ctx.diagnostics.hasError))
        }
    }
}
#endif
