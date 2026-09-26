#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InnerClassOuterReceiverCallTests {
    @Test func unqualifiedCallResolvesToOuterClassMember() throws {
        let ctx = makeContextFromSource("""
        class Outer(val value: Int) {
            fun fetch(index: Int): Int = value + index
            inner class Inner {
                fun compute(): Int = fetch(1)
            }
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError,
                "Expected unqualified outer member call to resolve, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
