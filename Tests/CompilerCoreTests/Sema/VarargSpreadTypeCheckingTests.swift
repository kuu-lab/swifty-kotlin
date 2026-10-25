@testable import CompilerCore
import Testing

@Suite
struct VarargSpreadTypeCheckingTests {
    @Test
    func acceptsPrimitiveArraySpreadArgument() throws {
        let ctx = makeContextFromSource("""
        fun f(vararg v: Int) = v.size
        fun use(values: IntArray) { f(*values) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected IntArray spread to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func rejectsSpreadOfNonArrayArgument() throws {
        let ctx = makeContextFromSource("""
        fun f(vararg v: Int) = v.size
        fun use() { f(*5) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "Expected `f(*5)` to be rejected")
    }
}
