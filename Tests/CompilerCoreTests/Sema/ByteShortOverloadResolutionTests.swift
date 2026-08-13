#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-186: Byte/Short overloads must be distinct and resolve to the correct overload.
@Suite
struct ByteShortOverloadResolutionTests {
    @Test func testByteAndShortOverloadsAndArrayLiteralNarrowing() throws {
        let sources: [String] = [
            """
            package sample0

            fun f(x: Byte): String = "byte"
            fun f(x: Short): String = "short"

            fun main() {
                println(f(1.toByte()))
                println(f(1.toShort()))
            }
            """,
            """
            package sample1

            fun main() {
                val bytes = byteArrayOf(1, 2, 3)
                bytes[0] = 9
                val shorts = shortArrayOf(1, 2, 3)
                shorts[0] = 9
                bytes.binarySearch(3)
                shorts.binarySearch(2)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected Byte/Short overloads and array operations to resolve without errors: \(ctx.diagnostics.diagnostics.map { $0.message })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let toByteCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toByte"
            }, "Expected 1.toByte() call")
            #expect(sema.bindings.exprType(for: toByteCall) == sema.types.byteType, "1.toByte() should have type Byte")

            let toShortCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toShort"
            }, "Expected 1.toShort() call")
            #expect(sema.bindings.exprType(for: toShortCall) == sema.types.shortType, "1.toShort() should have type Short")
        }
    }
}
#endif
