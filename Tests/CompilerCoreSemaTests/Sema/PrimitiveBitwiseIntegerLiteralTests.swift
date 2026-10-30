#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveBitwiseIntegerLiteralTests {
    @Test(arguments: [false, true])
    func longBitwiseOperatorsContextualizeBareIntegerLiterals(useCache: Bool) throws {
        let source = """
            fun test(x: Long): Boolean = (x and 3) == 0L
            fun andHex(x: Long): Long = x and 0xFF
            fun orMask(x: Long): Long = x or 3
            fun xorMask(x: Long): Long = x xor 3
            fun suffixed(x: Long): Long = x and 3L
            fun intMask(x: Int): Int = x and 3
            fun shift(x: Long): Long = x shl 56
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: useCache ? ["sema-cache"] : [],
                includeStdlib: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var bitwiseCallCount = 0
            for (index, expr) in ast.arena.exprs.enumerated() {
                guard case let .memberCall(receiverID, name, _, arguments, _) = expr,
                      arguments.count == 1,
                      ["and", "or", "xor"].contains(ctx.interner.resolve(name))
                else { continue }

                let callID = ExprID(rawValue: Int32(index))
                let receiverType = try #require(sema.bindings.exprType(for: receiverID))
                let argument = try #require(arguments.first)
                let expectedType = receiverType == sema.types.longType
                    ? sema.types.longType
                    : sema.types.intType
                #expect(sema.bindings.exprType(for: argument.expr) == expectedType)
                #expect(sema.bindings.exprType(for: callID) == receiverType)
                bitwiseCallCount += 1
            }
            #expect(bitwiseCallCount == 6)
        }
    }

    @Test func longBitwiseOperatorsDoNotAdaptIntVariables() throws {
        let source = """
            fun invalid(x: Long, mask: Int): Long = x and mask
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }
}
#endif
