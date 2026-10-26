#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SelfSubtypeCheckPropertyInitializerTests {
    @Test
    func narrowsThisInPropertyInitializerWhenCheckingItsOwnSubtype() throws {
        let source = """
        open class Variable {
            val lightVar: LightVariable = if (this is LightVariable) this else LightVariable()
        }

        class LightVariable() : Variable()

        fun box(): String {
            Variable()
            return "OK"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
