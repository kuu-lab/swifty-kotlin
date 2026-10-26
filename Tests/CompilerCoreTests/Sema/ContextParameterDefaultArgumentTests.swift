#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ContextParameterDefaultArgumentTests {
    @Test
    func namedContextParameterIsInDefaultValueScope() throws {
        try withTemporaryFile(contents: """
        class C(val value: Int)

        context(ctx: C)
        fun topLevel(value: C = ctx) = value.value

        fun enclosing() {
            context(ctx: C)
            fun local(value: C = ctx) = value.value
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                frontendFlags: ["opt-in=kotlin.ExperimentalContextParameters"],
                includeStdlib: false
            )

            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
