#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct PrimitiveArraySumByTests {
    private func context(_ source: String, useStdlibLibrary: Bool) -> CompilationContext {
        if useStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource(
            source,
            emit: useStdlibLibrary ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useStdlibLibrary
        )
        #expect((ctx.options.stdlibLibraryPath != nil) == useStdlibLibrary)
        return ctx
    }

    @Test(arguments: [false, true])
    func sumByResolvesForEveryPrimitiveArray(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            booleanArrayOf(true, false).sumBy { if (it) 1 else 0 }
            byteArrayOf(1, 2, 3).sumBy { it.toInt() }
            shortArrayOf(1, 2, 3).sumBy { it.toInt() }
            intArrayOf(1, 2, 3).sumBy { it }
            longArrayOf(1L, 2L, 3L).sumBy { it.toInt() }
            floatArrayOf(1f, 2f, 3f).sumBy { it.toInt() }
            doubleArrayOf(1.0, 2.0, 3.0).sumBy { it.toInt() }
            charArrayOf('A', 'B').sumBy { it.code }
            ubyteArrayOf(1.toUByte(), 2.toUByte()).sumBy { it.toUInt() }
            ushortArrayOf(1.toUShort(), 2.toUShort()).sumBy { it.toUInt() }
            uintArrayOf(1u, 2u).sumBy { it }
            ulongArrayOf(1uL, 2uL).sumBy { it.toUInt() }
            arrayOf(1, 2).sumBy { it }
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumBy", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        let expectedReceiverNames = [
            "BooleanArray", "ByteArray", "ShortArray", "IntArray",
            "LongArray", "FloatArray", "DoubleArray", "CharArray",
            "UByteArray", "UShortArray", "UIntArray", "ULongArray",
            "Array",
        ]
        #expect(calls.count == expectedReceiverNames.count)

        for (call, expectedName) in zip(calls, expectedReceiverNames) {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let receiver = try #require(signature.receiverType)
            guard let receiverSymbol = driverClassSymbol(receiver, sema: sema),
                  let receiverInfo = sema.symbols.symbol(receiverSymbol)
            else {
                Issue.record("Expected a nominal array receiver")
                continue
            }
            #expect(ctx.interner.resolve(receiverInfo.name) == expectedName)
        }
    }

    @Test(arguments: [false, true])
    func sumByDoubleResolvesForEveryPrimitiveArray(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            booleanArrayOf(true, false).sumByDouble { if (it) 1.0 else 0.0 }
            byteArrayOf(1, 2, 3).sumByDouble { it.toDouble() }
            shortArrayOf(1, 2, 3).sumByDouble { it.toDouble() }
            intArrayOf(1, 2, 3).sumByDouble { it.toDouble() }
            longArrayOf(1L, 2L, 3L).sumByDouble { it.toDouble() }
            floatArrayOf(1f, 2f, 3f).sumByDouble { it.toDouble() }
            doubleArrayOf(1.0, 2.0, 3.0).sumByDouble { it }
            charArrayOf('A', 'B').sumByDouble { it.code.toDouble() }
            ubyteArrayOf(1.toUByte(), 2.toUByte()).sumByDouble { it.toDouble() }
            ushortArrayOf(1.toUShort(), 2.toUShort()).sumByDouble { it.toDouble() }
            uintArrayOf(1u, 2u).sumByDouble { it.toDouble() }
            ulongArrayOf(1uL, 2uL).sumByDouble { it.toDouble() }
            arrayOf(1, 2).sumByDouble { it.toDouble() }
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumByDouble", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 13)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
        }
    }

    private func driverClassSymbol(_ type: TypeID, sema: SemaModule) -> SymbolID? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)) else {
            return nil
        }
        return classType.classSymbol
    }
}
#endif
