#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite
struct LibMetadataSerializationTests {
    @Test func testIndexedMetadataRoundTripUsesByteOffsets() throws {
        let records = [
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_first",
                fqName: "demo.first",
                arity: 1,
                receiverOwnerFQName: "demo.Receiver",
                typeSignature: "F1<I,I>",
                externalLinkName: "_kk_first"
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_kk_日本語",
                fqName: "demo.日本語",
                typeSignature: "I"
            ),
            MetadataRecord(
                kind: .class,
                mangledName: "_kk_owner",
                fqName: "demo.Owner",
                companionObjectFQName: "demo.Owner.Companion"
            ),
        ]

        let serialized = MetadataEncoder().serializeIndexed(records)
        #expect(serialized.hasPrefix("kklib-metadata-v2\n"))
        let file = try #require(IndexedMetadataFile(data: Data(serialized.utf8)))
        #expect(file.entries.count == records.count)
        #expect(file.entries[0].offset < file.entries[1].offset)
        #expect(file.entries.allSatisfy { $0.length > 0 })
        #expect(file.entries[0].record.receiverOwnerFQName == "demo.Receiver")
        #expect(file.entries[2].record.companionObjectFQName == "demo.Owner.Companion")
        #expect(file.entries.compactMap { file.record(for: $0).map(\.fqName) } == records.map(\.fqName))
        let decoded = MetadataDecoder().decode(serialized)
        #expect(decoded.map(\.fqName) == records.map(\.fqName))
        #expect(decoded[0].receiverOwnerFQName == "demo.Receiver")
        #expect(decoded[2].companionObjectFQName == "demo.Owner.Companion")
    }

    @Test func testIndexedLibraryImportDefersBodyUntilSignatureQuery() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        try """
        {
          "formatVersion": 1,
          "moduleName": "LazyMetadata",
          "metadata": "metadata.bin"
        }
        """.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let records = [
            MetadataRecord(kind: .package, mangledName: "_", fqName: "lazy"),
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_used",
                fqName: "lazy.used",
                arity: 1,
                receiverOwnerFQName: "lazy.Receiver",
                typeSignature: "F1<I,I>"
            ),
            MetadataRecord(kind: .function, mangledName: "_kk_unused", fqName: "lazy.unused", arity: 1, typeSignature: "F1<I,I>"),
        ]
        try MetadataEncoder().serializeIndexed(records)
            .write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "LazyConsumer",
            emit: .kirDump,
            searchPaths: [libDir.path]
        )
        let symbols = SymbolTable()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]
        let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )

        let used = try #require(work.importedBindings.first { ctx.interner.resolve($0.record.fqName.last!) == "used" })
        let unused = try #require(work.importedBindings.first { ctx.interner.resolve($0.record.fqName.last!) == "unused" })
        let package = try #require(work.importedBindings.first { $0.record.kind == .package })
        #expect(work.lazyLoaderState != nil)
        #expect(!used.isMaterialized)
        #expect(!unused.isMaterialized)
        #expect(used.record.receiverOwnerFQName?.map { ctx.interner.resolve($0) } == ["lazy", "Receiver"])
        #expect(symbols.parentSymbol(for: used.symbol) == package.symbol)
        #expect(symbols.functionSignature(for: used.symbol)?.parameterTypes.count == 1)
        #expect(used.isMaterialized)
        #expect(!unused.isMaterialized)
        #expect(symbols.parentSymbol(for: unused.symbol) == nil)
        #expect(!diagnostics.hasError)
    }

    @Test func testLazyImportedMetadataLoaderRunsOncePerSymbol() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        let name = interner.intern("Imported")
        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: [name],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        let typeName = interner.intern("ImportedType")
        let typeSymbol = symbols.define(
            kind: .class,
            name: typeName,
            fqName: [typeName],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        let functionName = interner.intern("importedFunction")
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: [functionName],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        var loadCount = 0
        symbols.setLazyImportedMetadataLoader { loadedSymbol in
            #expect(loadedSymbol == symbol || loadedSymbol == typeSymbol || loadedSymbol == functionSymbol)
            loadCount += 1
        }

        #expect(symbols.lookupByShortName(functionName) == [functionSymbol])
        #expect(loadCount == 0)
        _ = symbols.functionSignature(for: functionSymbol)
        _ = symbols.functionSignature(for: functionSymbol)
        _ = symbols.directSupertypes(for: symbol)
        _ = symbols.directSupertypes(for: symbol)
        _ = types.directNominalSupertypes(for: typeSymbol)
        _ = types.directNominalSupertypes(for: typeSymbol)

        #expect(loadCount == 3)
    }

    @Test func testIndexedStdlibNominalGenericsSurviveSyntheticRegistration() throws {
        TestStdlibCache.shared.prepare()
        let stdlibPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "LazyGenericConsumer",
            stdlibLibraryPath: stdlibPath
        )
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let diagnostics = DiagnosticEngine()
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]
        let phase = DataFlowSemaPhase()
        _ = phase.loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )
        phase.registerSyntheticCollectionStubs(
            symbols: symbols,
            types: types,
            interner: ctx.interner,
            bundledIndex: .empty
        )
        let listSymbol = try #require(symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
            ctx.interner.intern("List"),
        ]))
        let iterableSymbol = try #require(symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
            ctx.interner.intern("Iterable"),
        ]))

        let lifted = try #require(types.liftedNominalSupertypeArgs(
            from: listSymbol,
            childArgs: [.out(types.stringType)],
            to: iterableSymbol
        ))

        let liftedType: TypeID? = switch try #require(lifted.first) {
        case let .invariant(type), let .in(type), let .out(type): type
        case .star: nil
        }
        #expect(liftedType == types.stringType)
        #expect(!diagnostics.hasError)
    }

    @Test func testIndexedStdlibCompanionPropertyMaterializesFromShell() throws {
        TestStdlibCache.shared.prepare()
        let stdlibPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "LazyCompanionConsumer",
            stdlibLibraryPath: stdlibPath
        )
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let diagnostics = DiagnosticEngine()
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]
        _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )

        let ownerFQName = ["kotlin", "KotlinVersion"].map(ctx.interner.intern)
        let companionFQName = ownerFQName + [ctx.interner.intern("Companion")]
        let currentFQName = companionFQName + [ctx.interner.intern("CURRENT")]
        let owner = try #require(symbols.lookup(fqName: ownerFQName))
        let companion = try #require(symbols.lookup(fqName: companionFQName))
        let current = try #require(symbols.lookup(fqName: currentFQName))

        #expect(symbols.companionObjectSymbol(for: owner) == companion)
        #expect(symbols.parentSymbol(for: companion) == owner)
        #expect(symbols.parentSymbol(for: current) == companion)
        #expect(symbols.propertyType(for: current) != nil)
        #expect(!diagnostics.hasError)
    }

    // MARK: - MetadataSerializer Round-Trip Tests

    @Test func testMetadataEncoderDecoderRoundTripForFunctionRecord() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_ext_id",
            fqName: "ext.id",
            arity: 1,
            isSuspend: false,
            isInline: true,
            typeSignature: "F1<I,I>",
            valueParameterAllowsNonLocalReturn: [false],
            externalLinkName: "_ext_id"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        let r = decoded[0]
        #expect(r.kind == .function)
        #expect(r.mangledName == "_kk_ext_id")
        #expect(r.fqName == "ext.id")
        #expect(r.arity == 1)
        #expect(r.isSuspend == false)
        #expect(r.isInline == true)
        #expect(r.typeSignature == "F1<I,I>")
        #expect(r.valueParameterAllowsNonLocalReturn == [false])
        #expect(r.externalLinkName == "_ext_id")
    }

    @Test func testMetadataEncoderDecoderRoundTripForClassWithLayout() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Box",
            fqName: "ext.Box",
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 1,
            declaredItableSize: 1,
            superFQName: "ext.Base",
            fieldOffsets: "ext.Box.x@2,ext.Box.y@3",
            vtableSlots: "ext.Box.get#0#0@0",
            itableSlots: "ext.IFace@0"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 1)
        let r = decoded[0]
        #expect(r.kind == .class)
        #expect(r.fqName == "ext.Box")
        #expect(r.declaredFieldCount == 2)
        #expect(r.declaredInstanceSizeWords == 4)
        #expect(r.declaredVtableSize == 1)
        #expect(r.declaredItableSize == 1)
        #expect(r.superFQName == "ext.Base")
        #expect(r.fieldOffsets == "ext.Box.x@2,ext.Box.y@3")
        #expect(r.vtableSlots == "ext.Box.get#0#0@0")
        #expect(r.itableSlots == "ext.IFace@0")
    }

    @Test func testSyntheticValueClassAnchorPreservesUnderlyingTypeMetadata() throws {
        let encoder = MetadataEncoder()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let stableRef = symbols.define(
            kind: .class,
            name: interner.intern("StableRef"),
            fqName: [
                interner.intern("kotlinx"),
                interner.intern("cinterop"),
                interner.intern("StableRef"),
            ],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .valueType]
        )
        symbols.setValueClassUnderlyingType(types.intType, for: stableRef)
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 0,
                instanceSizeWords: 2,
                fieldOffsets: [:],
                vtableSlots: [:],
                itableSlots: [:],
                superClass: nil
            ),
            for: stableRef
        )

        let records = encoder.buildRecords(
            symbols: symbols,
            types: types,
            moduleName: "Stdlib",
            interner: interner,
            functionLinkNames: [:],
            includeSynthetic: false,
            includeSyntheticNominalAnchors: true
        )

        let record = try #require(records.first { $0.fqName == "kotlinx.cinterop.StableRef" })
        #expect(record.isValueClass)
        #expect(record.valueClassUnderlyingTypeSig == "I")

        let serialized = encoder.serialize(records)
        #expect(serialized.contains("fq=kotlinx.cinterop.StableRef"))
        #expect(serialized.contains("valueClass=1 valueUnderlying=I"))

        let decoded = MetadataDecoder().decode(serialized)
        let decodedRecord = try #require(decoded.first { $0.fqName == "kotlinx.cinterop.StableRef" })
        #expect(decodedRecord.valueClassUnderlyingTypeSig == "I")
    }

    @Test func testMetadataEncoderDecoderRoundTripForDataClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_data_Point",
            fqName: "demo.Point",
            isDataClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("dataClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].isDataClass)
        #expect(!decoded[0].isSealedClass)
    }

    @Test func testMetadataEncoderDecoderRoundTripForOpenClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_open_Base",
            fqName: "demo.Base",
            isOpenClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("openClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].isOpenClass)
    }

    @Test func testMetadataModalityRoundTripsForNominalsAndMembers() {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_kk_abstract_Collection",
                fqName: "demo.AbstractCollection",
                isOpenClass: true,
                modality: .abstract
            ),
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_open_iterator",
                fqName: "demo.AbstractCollection.iterator",
                modality: .open
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_kk_abstract_size",
                fqName: "demo.AbstractCollection.size",
                modality: .abstract
            ),
        ]
        let serialized = MetadataEncoder().serialize(records)
        #expect(serialized.contains("modality=abstract"))
        #expect(serialized.contains("modality=open"))

        let decoded = MetadataDecoder().decode(serialized)
        #expect(decoded.map(\.modality) == [.abstract, .open, .abstract])

        let legacy = MetadataDecoder().decode(
            "symbols=1\nfunction _kk_legacy fq=demo.legacy schema=v1 arity=0 sig=F0<I>\n"
        )
        #expect(legacy.count == 1)
        #expect(legacy[0].modality == .final)
    }

    @Test func testMetadataEncoderDecoderRoundTripForSealedClassFlag() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_sealed_Shape",
            fqName: "demo.Shape",
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(!decoded[0].isDataClass)
        #expect(decoded[0].isSealedClass)
    }

    @Test func testMetadataEncoderDecoderRoundTripForAnnotations() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["Use newMethod instead"],
                useSiteTarget: nil
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.jvm.JvmStatic",
                arguments: [],
                useSiteTarget: "get"
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_old",
            fqName: "demo.oldMethod",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("annotations="))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 2)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Deprecated")
        #expect(decoded[0].annotations[0].arguments == ["Use newMethod instead"])
        #expect(decoded[0].annotations[0].useSiteTarget == nil)
        #expect(decoded[0].annotations[1].annotationFQName == "kotlin.jvm.JvmStatic")
        #expect(decoded[0].annotations[1].arguments == [])
        #expect(decoded[0].annotations[1].useSiteTarget == "get")
    }

    @Test func testMetadataEncoderDecoderRoundTripForWasExperimentalAnnotation() {
        let annotations = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.WasExperimental",
                arguments: ["markerClass = demo.ExperimentalApi::class"],
                useSiteTarget: nil
            ),
        ]
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_stable_api",
            fqName: "demo.stableApi",
            annotations: annotations
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.WasExperimental")
        #expect(decoded[0].annotations[0].arguments == ["markerClass = demo.ExperimentalApi::class"])
        #expect(decoded[0].annotations[0].useSiteTarget == nil)
    }

    @Test func testMetadataEncoderDecoderRoundTripForDataAndSealedBothSet() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_ext_Weird",
            fqName: "ext.Weird",
            declaredFieldCount: 0,
            declaredInstanceSizeWords: 0,
            isDataClass: true,
            isSealedClass: true
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("dataClass=1"))
        #expect(serialized.contains("sealedClass=1"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "ext.Weird")
        #expect(decoded[0].isDataClass)
        #expect(decoded[0].isSealedClass)
    }

    @Test func testMetadataDecoderAcceptsLegacyRecordsWithoutSchema() {
        let legacy = """
        symbols=1
        class _kk_ext_C fq=ext.C fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(legacy)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "ext.C")
    }

    @Test func testMetadataDecoderRejectsRecordsWithUnsupportedSchema() {
        let future = """
        symbols=1
        class _kk_ext_C fq=ext.C schema=v2 fields=0 layoutWords=3 vtable=0 itable=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(future)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataRoundTripMultipleRecords() {
        let records = [
            MetadataRecord(
                kind: .class,
                mangledName: "_kk_Point",
                fqName: "demo.Point",
                declaredFieldCount: 2,
                declaredInstanceSizeWords: 4,
                isDataClass: true,
                annotations: [
                    MetadataAnnotationRecord(annotationFQName: "kotlin.Serializable"),
                ]
            ),
            MetadataRecord(
                kind: .function,
                mangledName: "_kk_demo_greet",
                fqName: "demo.greet",
                arity: 1,
                isSuspend: true,
                typeSignature: "F1<S,U>"
            ),
            MetadataRecord(
                kind: .property,
                mangledName: "_kk_demo_name",
                fqName: "demo.name",
                typeSignature: "S"
            ),
        ]
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize(records)
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)

        #expect(decoded.count == 3)

        #expect(decoded[0].kind == .class)
        #expect(decoded[0].fqName == "demo.Point")
        #expect(decoded[0].isDataClass)
        #expect(decoded[0].annotations.count == 1)
        #expect(decoded[0].annotations[0].annotationFQName == "kotlin.Serializable")

        #expect(decoded[1].kind == .function)
        #expect(decoded[1].fqName == "demo.greet")
        #expect(decoded[1].arity == 1)
        #expect(decoded[1].isSuspend)
        #expect(decoded[1].typeSignature == "F1<S,U>")

        #expect(decoded[2].kind == .property)
        #expect(decoded[2].fqName == "demo.name")
        #expect(decoded[2].typeSignature == "S")
    }

    @Test func testMetadataImportRestoresDataClassFlagViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtDataClass",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Point fq=ext.Point schema=v1 fields=2 layoutWords=4 vtable=0 itable=0 dataClass=1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DataClassImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let pointSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Point" && symbol.kind == .class
            }
            #expect(pointSymbol != nil)
            #expect(pointSymbol?.flags.contains(.dataType) ?? false)
            #expect(!(pointSymbol?.flags.contains(.sealedType) ?? true))
        }
    }

    @Test func testMetadataImportRestoresOpenClassFlagViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtOpenClass",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Base fq=ext.Base schema=v1 fields=0 layoutWords=2 vtable=0 itable=0 openClass=1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "OpenClassImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let baseSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Base" && symbol.kind == .class
            }
            #expect(baseSymbol != nil)
            #expect(baseSymbol?.flags.contains(.openType) ?? false)
            #expect(!(baseSymbol?.flags.contains(.sealedType) ?? true))
        }
    }

    // BUG-KSP-1217-PHANTOM-TYPE-PARAMS: a function's type parameter is
    // "phantom" when it is declared but never referenced by the receiver,
    // value parameters, or return type -- only used inside the function body
    // via an explicit type argument (e.g.
    // `kotlin.native.concurrent.callContinuation1<T1>`). Metadata import used
    // to reconstruct `typeParameterSymbols` purely by scanning the decoded
    // function *type* structurally, silently dropping such parameters, so an
    // explicit-type-argument call like `callContinuation1<Int>()` failed
    // overload resolution with a bogus arity mismatch. `ext.phantom` below
    // mirrors `fun <T> Any.phantom(): Unit`: T is declared but unused in the
    // signature. Its own `typeParameter` record's fqName
    // (`ext.phantom.$1.T`) mirrors the `<ownerFQName>.$<id>.<name>` shape
    // `HeaderCollection.swift`'s `collectFunctionTypeParameters` caller emits
    // for a function's declared type parameters, which import now uses to
    // restore the correct type parameter count.
    @Test func testMetadataImportRestoresPhantomTypeParameterViaLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ExtPhantomTypeParam",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        function _kk_ext_phantom fq=ext.phantom schema=v1 arity=0 suspend=0 inline=0 operator=0 sig=F0<RA,U>
        typeParameter _kk_ext_phantom_T fq=ext.phantom.$1.T schema=v1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "PhantomTypeParamImport",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let phantomSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "phantom" && symbol.kind == .function
            }
            let phantomSymbolID = try #require(phantomSymbol?.id)
            let signature = try #require(sema.symbols.functionSignature(for: phantomSymbolID))
            #expect(signature.typeParameterSymbols.count == 1)
        }
    }

    // MARK: - MetadataDecoder.symbolKindFromMetadata Unit Tests

    @Test func testSymbolKindFromMetadataReturnsCorrectKindForAllTokens() {
        let decoder = MetadataDecoder()
        #expect(decoder.symbolKindFromMetadata("package") == .package)
        #expect(decoder.symbolKindFromMetadata("class") == .class)
        #expect(decoder.symbolKindFromMetadata("interface") == .interface)
        #expect(decoder.symbolKindFromMetadata("object") == .object)
        #expect(decoder.symbolKindFromMetadata("enumClass") == .enumClass)
        #expect(decoder.symbolKindFromMetadata("annotationClass") == .annotationClass)
        #expect(decoder.symbolKindFromMetadata("typeAlias") == .typeAlias)
        #expect(decoder.symbolKindFromMetadata("function") == .function)
        #expect(decoder.symbolKindFromMetadata("constructor") == .constructor)
        #expect(decoder.symbolKindFromMetadata("property") == .property)
        #expect(decoder.symbolKindFromMetadata("field") == .field)
        #expect(decoder.symbolKindFromMetadata("typeParameter") == .typeParameter)
        #expect(decoder.symbolKindFromMetadata("valueParameter") == .valueParameter)
        #expect(decoder.symbolKindFromMetadata("local") == .local)
        #expect(decoder.symbolKindFromMetadata("label") == .label)
    }

    @Test func testSymbolKindFromMetadataReturnsNilForUnknownToken() {
        let decoder = MetadataDecoder()
        #expect(decoder.symbolKindFromMetadata("") == nil)
        #expect(decoder.symbolKindFromMetadata("unknown") == nil)
        #expect(decoder.symbolKindFromMetadata("CLASS") == nil)
        #expect(decoder.symbolKindFromMetadata("Function") == nil)
        #expect(decoder.symbolKindFromMetadata("backingField") == .backingField)
    }

    // MARK: - MetadataDecoder Edge Cases

    @Test func testMetadataDecoderReturnsEmptyForEmptyInput() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("").count == 0)
    }

    @Test func testMetadataDecoderReturnsEmptyForOnlyHeader() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("symbols=5\n").count == 0)
    }

    @Test func testMetadataDecoderReturnsEmptyForWhitespaceOnly() {
        let decoder = MetadataDecoder()
        #expect(decoder.decode("   \n  \n").count == 0)
    }

    @Test func testMetadataDecoderSkipsLinesWithUnknownKind() {
        let metadata = """
        symbols=2
        unknownKind _kk_foo fq=demo.Foo schema=v1
        function _kk_bar fq=demo.bar schema=v1 arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].fqName == "demo.bar")
    }

    @Test func testMetadataDecoderSkipsLinesWithoutFqField() {
        let metadata = """
        symbols=1
        function _kk_bar arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataDecoderSkipsLinesWithEmptyFqField() {
        let metadata = """
        symbols=1
        function _kk_bar fq= arity=0 suspend=0 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 0)
    }

    @Test func testMetadataDecoderIgnoresTokensWithoutEqualsSign() {
        // Tokens without '=' should be silently skipped (except kind and mangledName)
        let metadata = """
        symbols=1
        function _kk_bar fq=demo.bar schema=v1 randomtoken arity=2 suspend=1 inline=0
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].arity == 2)
        #expect(decoded[0].isSuspend)
    }

    @Test func testMetadataDecoderIgnoresUnknownKeyValuePairs() {
        let metadata = """
        symbols=1
        class _kk_Foo fq=demo.Foo schema=v1 futureKey=futureValue fields=1 layoutWords=2
        """
        let decoder = MetadataDecoder()
        let decoded = decoder.decode(metadata)
        #expect(decoded.count == 1)
        #expect(decoded[0].fqName == "demo.Foo")
        #expect(decoded[0].declaredFieldCount == 1)
    }

    // MARK: - MetadataEncoder Edge Cases

    @Test func testMetadataEncoderSerializeEmptyRecordsArray() {
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([])
        #expect(serialized == "symbols=0\n")
    }

    @Test func testMetadataEncoderDoesNotEmitDataClassWhenFalse() {
        let record = MetadataRecord(
            kind: .class,
            mangledName: "_kk_Foo",
            fqName: "demo.Foo"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(!serialized.contains("dataClass="))
        #expect(!serialized.contains("sealedClass="))
        #expect(!serialized.contains("annotations="))
    }

    @Test func testMetadataEncoderDoesNotEmitAnnotationsWhenEmpty() {
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_foo",
            fqName: "demo.foo",
            annotations: []
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(!serialized.contains("annotations="))
    }

    // MARK: - Round-Trip for Each Symbol Kind

    @Test func testMetadataRoundTripForPropertyWithTypeSignature() {
        let record = MetadataRecord(
            kind: .property,
            mangledName: "_kk_demo_name",
            fqName: "demo.name",
            typeSignature: "S"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=S"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .property)
        #expect(decoded[0].fqName == "demo.name")
        #expect(decoded[0].typeSignature == "S")
    }

    @Test func testMetadataRoundTripForFieldWithTypeSignature() {
        let record = MetadataRecord(
            kind: .field,
            mangledName: "_kk_demo_x",
            fqName: "demo.x",
            typeSignature: "I"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=I"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .field)
        #expect(decoded[0].typeSignature == "I")
    }

    @Test func testMetadataRoundTripForTypeAliasWithTypeSignature() {
        let record = MetadataRecord(
            kind: .typeAlias,
            mangledName: "_kk_demo_ID",
            fqName: "demo.ID",
            typeSignature: "L"
        )
        let encoder = MetadataEncoder()
        let serialized = encoder.serialize([record])
        #expect(serialized.contains("sig=L"))

        let decoder = MetadataDecoder()
        let decoded = decoder.decode(serialized)
        #expect(decoded.count == 1)
        #expect(decoded[0].kind == .typeAlias)
        #expect(decoded[0].fqName == "demo.ID")
        #expect(decoded[0].typeSignature == "L")
    }
}
#endif
