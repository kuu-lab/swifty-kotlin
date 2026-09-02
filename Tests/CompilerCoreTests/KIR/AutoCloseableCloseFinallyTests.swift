#if canImport(Testing)
@testable import CompilerCore
import Foundation
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected AutoCloseable.use source to compile: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let closeFinallyCalls = body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
                guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "closeFinally"
                else {
                    return nil
                }
                return (arguments, canThrow)
            }
            #expect(closeFinallyCalls.count == 1, "Expected one source-backed closeFinally call in main KIR")
            #expect(closeFinallyCalls.first?.arguments.count == 2)
            #expect(closeFinallyCalls.first?.canThrow == true)
        }
    }
}
#endif
