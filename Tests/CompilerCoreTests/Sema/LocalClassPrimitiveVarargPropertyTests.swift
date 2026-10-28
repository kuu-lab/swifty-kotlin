@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalClassPrimitiveVarargPropertyTests {
    private func check(_ source: String, fromSource: Bool) throws -> CompilationContext {
        if !fromSource { TestStdlibCache.shared.prepare() }
        let context = makeContextFromSources([
            source,
            "package shadowed\nclass Int",
        ], allowDefaultStdlibLibrary: !fromSource)
        if fromSource {
            #expect(context.options.stdlibLibraryPath == nil && context.options.includeStdlib)
        } else {
            _ = try #require(context.options.stdlibLibraryPath)
        }
        try runSema(context)
        #expect(context.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty, "\(context.diagnostics.diagnostics)")
        return context
    }

    @Test(arguments: [false, true])
    func primitiveAliasesAndReferenceControlsRetainTheirArrayTypes(fromSource: Bool) throws {
        let primitives = ["Boolean", "Byte", "Short", "Int", "Long", "Char", "Float", "Double",
                          "UByte", "UShort", "UInt", "ULong"]
        let declarations = primitives.map { type in
            "class \(type)Holder(vararg val values: \(type)) { fun read(): \(type)Array = values }"
        }.joined(separator: "\n")
        let context = try check("""
        @file:OptIn(ExperimentalUnsignedTypes::class)
        import shadowed.Int as UserInt
        typealias Count = Int
        typealias Tag = ULong
        fun host() {
            \(declarations)
            class Aliased(vararg var counts: Count) {
                constructor(text: String) : this()
                fun read(): IntArray = counts
            }
            class UnsignedAlias(vararg val tags: Tag) { fun read(): ULongArray = tags }
            class References(vararg val words: String) { fun read(): Array<out String> = words }
            class Nullable(vararg val numbers: Int?) { fun read(): Array<out Int?> = numbers }
            class NullableUnsigned(vararg val tags: ULong?) { fun read(): Array<out ULong?> = tags }
            class Nominal(vararg val values: UserInt) { fun read(): Array<out UserInt> = values }
        }
        """, fromSource: fromSource)
        let sema = try #require(context.sema)
        let expected = Dictionary(uniqueKeysWithValues: primitives.map { ($0 + "Holder", $0 + "Array") })
            .merging(["Aliased": "IntArray", "UnsignedAlias": "ULongArray", "References": "Array",
                      "Nullable": "Array", "NullableUnsigned": "Array", "Nominal": "Array"]) { _, new in new }
        for (ownerName, arrayName) in expected {
            let owner = try #require(sema.symbols.allSymbols().first {
                $0.kind == .class && context.interner.resolve($0.name) == ownerName
            })
            let property = try #require(sema.symbols.allSymbols().first {
                $0.kind == .property && sema.symbols.parentSymbol(for: $0.id) == owner.id
            })
            let type = try #require(sema.symbols.propertyType(for: property.id))
            guard case let .classType(array) = sema.types.kind(of: type) else {
                Issue.record("Expected array property for \(ownerName)")
                continue
            }
            #expect(context.interner.resolve(sema.symbols.symbol(array.classSymbol)?.name ?? owner.name) == arrayName)
            #expect(array.args.count == (arrayName == "Array" ? 1 : 0))
            if ownerName == "Nominal" {
                let classifier = try #require(sema.symbols.lookup(fqName: ["shadowed", "Int"].map(context.interner.intern)))
                let element = sema.types.make(.classType(ClassType(classSymbol: classifier)))
                #expect(array.args == [.out(element)])
            }
            if arrayName != "Array" {
                let constructor = try #require(sema.symbols.allSymbols().first {
                    $0.kind == .constructor && sema.symbols.parentSymbol(for: $0.id) == owner.id
                        && sema.symbols.functionSignature(for: $0.id)?.valueParameterIsVararg.first == true
                })
                let signature = try #require(sema.symbols.functionSignature(for: constructor.id))
                #expect(signature.valueParameterIsVararg == [true])
                guard case .primitive(_, .nonNull) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("The constructor signature must retain its primitive element type")
                    continue
                }
            }
        }
        #expect(context.diagnostics.diagnostics.isEmpty, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func primitivePropertyCannotBeUsedAsAGenericArray(fromSource: Bool) throws {
        if !fromSource { TestStdlibCache.shared.prepare() }
        let context = makeContextFromSource("""
        fun host() {
            class Holder(vararg val values: Int)
            val wrong: Array<out Int> = Holder(1).values
        }
        """, allowDefaultStdlibLibrary: !fromSource)
        if fromSource {
            #expect(context.options.stdlibLibraryPath == nil && context.options.includeStdlib)
        } else {
            _ = try #require(context.options.stdlibLibraryPath)
        }
        try runSema(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(context.diagnostics.diagnostics)")
        #expect(errors.first?.code == "KSWIFTK-TYPE-0001", "\(errors)")
        #expect(errors.first?.primaryRange.map { context.sourceManager.lineColumn(of: $0.start).line == 3 } == true)
    }

    @Test(arguments: [false, true])
    func unsignedVarargConsentMatrix(fromSource: Bool) throws {
        let cases = [("", 1), ("property:OptIn", 1), ("OptIn", 0), ("param:OptIn", 0), ("file:OptIn", 0)]
        let sources = cases.enumerated().map { index, entry in
            let annotation = entry.0
            let consent = annotation.isEmpty || annotation == "file:OptIn"
                ? "" : "@\(annotation)(ExperimentalUnsignedTypes::class) "
            let fileConsent = annotation == "file:OptIn" ? "@file:OptIn(ExperimentalUnsignedTypes::class)\n" : ""
            return """
            \(fileConsent)package consentprobe\(index)
            fun host() {
                class Holder(\(consent)vararg val tags: ULong)
            }
            """
        }
        if !fromSource { TestStdlibCache.shared.prepare() }
        let context = makeContextFromSources(sources, allowDefaultStdlibLibrary: !fromSource)
        if fromSource {
            #expect(context.options.stdlibLibraryPath == nil && context.options.includeStdlib)
        } else {
            _ = try #require(context.options.stdlibLibraryPath)
        }
        try runSema(context)
        #expect(context.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty, "\(context.diagnostics.diagnostics)")
        #expect(context.diagnostics.diagnostics.count == 2, "\(context.diagnostics.diagnostics)")
        for (index, entry) in cases.enumerated() {
            let file = try #require(context.sourceManager.fileID(forPath: context.options.inputs[index]))
            let diagnostics = context.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == file }
            #expect(diagnostics.count == entry.1, "\(entry.0): \(diagnostics)")
            #expect(diagnostics.allSatisfy {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
                    && $0.message.contains("kotlin.ExperimentalUnsignedTypes")
                    && $0.primaryRange.map { context.sourceManager.lineColumn(of: $0.start).line == 3 } == true
            }, "\(diagnostics)")
        }
    }
}
