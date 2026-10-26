#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenCallableReferenceInvocationTests {
    @Test
    func immediatelyInvokesCallableReferenceSelectedFromWhenBranches() throws {
        let ctx = makeContextFromSource("""
        fun decodeValue(value: String): Any {
            return when (value[0]) {
                'F' -> String::toFloat
                'I' -> String::toInt
                else -> throw IllegalArgumentException("x")
            }(value.substring(2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
