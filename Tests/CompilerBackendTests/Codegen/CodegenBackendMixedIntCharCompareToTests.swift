#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendMixedIntCharCompareToTests {
    @Test
    func testComparisonUsesIntCharCompareToExtension() throws {
        let source = """
        operator fun Int.compareTo(c: Char) = 0
        fun foo(x: Int, y: Char): String {
            if (x < y) throw Error()
            return "OK"
        }
        fun main() { println(foo(42, 'O')) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MixedIntCharCompareTo",
            expected: "OK\n"
        )
    }
}
#endif
