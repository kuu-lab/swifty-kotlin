#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ValueKeywordExpressionBodyTests {
    @Test
    func bareValueInExpressionBodyPreservesNextFunctionBody() throws {
        let ctx = makeContextFromSource("""
        class Holder(var value: Int)

        fun Holder.read(): Int = value

        fun Holder.other(): Int = 0
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    @Test
    func bareValueAfterAssignmentNewlinePreservesNextFunctionBody() throws {
        let ctx = makeContextFromSource("""
        class Holder(var value: Int)

        fun Holder.read(): Int =
            value

        fun Holder.other(): Int = 0
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }
}
#endif
