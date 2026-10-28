@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ArrayWithIndexTests {
    @Test(arguments: [false, true])
    func primitiveIndexedValuesKeepElementTypes(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = ["Byte", "Short", "Int", "Long"].map { type in
            """
            fun check\(type)(xs: \(type)Array) {
                val indexed: Iterable<IndexedValue<\(type)>> = xs.withIndex()
                val iterator: \(type)Iterator = xs.iterator()
                for ((i, x) in indexed) {
                    val index: Int = i
                    val value: \(type) = x
                }
            }
            """
        }.joined(separator: "\n") + "\nfun main() {}"
        let ctx = makeContextFromSource(
            source, emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["withIndex", "iterator"] {
            let calls = memberCallExprIDs(named: name, in: ast, interner: ctx.interner)
                .filter { isUserSourceExpr($0, in: ctx) }
            #expect(calls.count == 4)
            for call in calls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName ==
                    ["kotlin", "collections", name].map(ctx.interner.intern))
            }
        }
    }

    @Test(arguments: [false, true])
    func unsignedPrimitiveArraysResolveIterationExtensions(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
            @OptIn(ExperimentalUnsignedTypes::class)
            fun checkUnsignedArrays(
                bytes: UByteArray,
                shorts: UShortArray,
                ints: UIntArray,
                longs: ULongArray
            ) {
                val byteIndexed: Iterable<IndexedValue<UByte>> = bytes.withIndex()
                val shortIndexed: Iterable<IndexedValue<UShort>> = shorts.withIndex()
                val intIndexed: Iterable<IndexedValue<UInt>> = ints.withIndex()
                val longIndexed: Iterable<IndexedValue<ULong>> = longs.withIndex()
                val byteIterator: Iterator<UByte> = bytes.iterator()
                val shortIterator: Iterator<UShort> = shorts.iterator()
                val intIterator: Iterator<UInt> = ints.iterator()
                val longIterator: Iterator<ULong> = longs.iterator()
            }
            fun main() {}
            """
        let ctx = makeContextFromSource(
            source, emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for name in ["withIndex", "iterator"] {
            let calls = memberCallExprIDs(named: name, in: ast, interner: ctx.interner)
                .filter { isUserSourceExpr($0, in: ctx) }
            #expect(calls.count == 4)
            for call in calls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName ==
                    ["kotlin", "collections", name].map(ctx.interner.intern))
            }
        }
    }

    @Test
    func unsignedArrayWithIndexResolvesInBracketDestructuringLoops() throws {
        let source = """
            fun withIndexAndValue(values: UIntArray) {
                for ([i, ui] in values.withIndex()) {
                    val index: Int = i
                    val value: UInt = ui
                }
            }
            fun withValueOnly(values: UIntArray) {
                for ([_, ui] in values.withIndex()) {
                    val value: UInt = ui
                }
            }
            fun withIndexOnly(values: UIntArray) {
                for ([i, _] in values.withIndex()) {
                    val index: Int = i
                }
            }
            fun withSizeOnlyConstructor() {
                for ([i, ui] in UIntArray(2).withIndex()) {
                    val index: Int = i
                    val value: UInt = ui
                }
            }
            fun main() {}
            """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error
        }
        #expect(errors.isEmpty, "Unexpected unsigned withIndex/for-in diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "withIndex", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 4)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName ==
                ["kotlin", "collections", "withIndex"].map(ctx.interner.intern))
        }
    }
}
