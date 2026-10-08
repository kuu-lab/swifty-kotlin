#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AutoCloseableCloseFinallyKIRTests {
    @Test
    func testAutoCloseableUseLowersThroughSourceBackedCloseFinally() throws {
        let source = """
        class Resource : AutoCloseable {
            override fun close() {}
        }

        fun main() {
            Resource().use { "body" }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected AutoCloseable.use source to compile: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let sema = try #require(ctx.sema)
        let closeFinally = try #require(sema.symbols.lookup(fqName: ["kotlin", "closeFinally"].map(ctx.interner.intern)))
        let closeFinallyCalls = kirCalls(to: closeFinally, in: body)
        #expect(closeFinallyCalls.count == 1, "Expected one source-backed closeFinally call in main KIR")
        #expect(closeFinallyCalls.first?.arguments.count == 2)
        #expect(closeFinallyCalls.first?.canThrow == true)
    }
}
#endif
