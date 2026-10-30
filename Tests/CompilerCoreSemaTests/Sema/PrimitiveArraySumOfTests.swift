#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct PrimitiveArraySumOfTests {
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
    func sumOfResolvesForEveryPrimitiveArray(useStdlibLibrary: Bool) throws {
        let ctx = context("""
        fun main() {
            booleanArrayOf(true, false).sumOf { if (it) 1 else 0 }
            byteArrayOf(1, 2, 3).sumOf { it.toInt() }
            shortArrayOf(1, 2, 3).sumOf { it.toInt() }
            intArrayOf(1, 2, 3).sumOf { it }
            longArrayOf(1L, 2L, 3L).sumOf { it }
            floatArrayOf(1f, 2f, 3f).sumOf { it.toDouble() }
            doubleArrayOf(1.0, 2.0, 3.0).sumOf { it }
            charArrayOf('A', 'B').sumOf { it.code }
        }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        let expectedReceiverNames = [
            "BooleanArray", "ByteArray", "ShortArray", "IntArray",
            "LongArray", "FloatArray", "DoubleArray", "CharArray",
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
                Issue.record("Expected a nominal primitive-array receiver")
                continue
            }
            #expect(ctx.interner.resolve(receiverInfo.name) == expectedName)
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
