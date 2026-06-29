#if canImport(Testing)
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
