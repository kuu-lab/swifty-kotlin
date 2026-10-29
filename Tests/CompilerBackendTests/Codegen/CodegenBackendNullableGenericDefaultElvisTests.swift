@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNullableGenericDefaultElvisTests {
    @Test(arguments: [0, 2])
    func nullableGenericDefaultArgumentElvisReturnsFallback(optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = """
        fun <T : Any?> someFunc(a: T, arg: T? = null): T = arg ?: a

        fun box(): String {
            var key: String? = null
            key = someFunc("a")
            if (key != "a") return "FAIL1"
            key = someFunc("a", "b")
            if (key != "b") return "FAIL2"

            var key1: Int? = null
            key1 = someFunc(42)
            if (key1 != 42) return "FAIL3"
            key1 = someFunc(42, 24)
            if (key1 != 24) return "FAIL3"
            return "OK"
        }

        fun main() {
            println(box())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NullableGenericDefaultArgumentElvis",
            expected: "OK\n",
            optLevel: optLevel
        )
    }
}
#endif
