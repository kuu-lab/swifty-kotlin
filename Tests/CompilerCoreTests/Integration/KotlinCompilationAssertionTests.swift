#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct KotlinCompilationAssertionTests {
    @Test func testCompile_assertCalls() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            assert(true)
            assert(1 < 2) { "ok" }
        }
        """)
    }
}
#endif
