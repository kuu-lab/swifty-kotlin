#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LabeledReturnReachabilityTests {

    @Test func testStatementsAfterLocalReturnFromInlineLambdaRemainReachable() throws {
        let source = """
        fun main() {
            run r@{
                println("run")
                return@r
                throw IllegalStateException("unreachable in lambda")
            }
            listOf(1, 2).forEach lit@{ println(it) }
        }
        fun conditional(flag: Boolean) {
            run branch@{ if (flag) return@branch else return@branch }
            println("after conditional")
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = diagnosticsForPath(ctx.options.inputs[0], in: ctx)
        let unreachableDiagnostics = diagnostics.filter { $0.code == "KSWIFTK-SEMA-0096" }
        #expect(unreachableDiagnostics.count == 1, "Expected only the statement inside the lambda to be unreachable, got: \(diagnostics)")
        let throwOffset = source.components(separatedBy: "throw IllegalStateException")[0].utf8.count
        #expect(unreachableDiagnostics.first?.primaryRange?.start.offset == throwOffset)
    }

    @Test func testStatementsAfterLocalReturnFromNonInlineLambdaRemainReachable() throws {
        let source = """
        fun <T> consume(block: () -> T): T = block()
        fun main() {
            consume local@{ return@local }
            println("after")
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = diagnosticsForPath(ctx.options.inputs[0], in: ctx)
        #expect(!diagnostics.contains { $0.code == "KSWIFTK-SEMA-0096" }, "Got: \(diagnostics)")
    }

    @Test func testNonLocalReturnFromInlineLambdaStillMakesFollowingCodeUnreachable() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            run { return }
            println("unreachable")
        }
        """)
        try runSema(ctx)

        let diagnostics = diagnosticsForPath(ctx.options.inputs[0], in: ctx)
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-0096" }, "Got: \(diagnostics)")
    }
}
#endif
