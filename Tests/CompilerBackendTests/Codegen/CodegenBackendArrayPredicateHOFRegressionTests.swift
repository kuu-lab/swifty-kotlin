#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendArrayPredicateHOFRegressionTests {

    @Test
    func testCodegenArrayAnyAllNonePredicatesDoNotCrash() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.any { it > 2 })
            println(arr.all { it > 0 })
            println(arr.none { it > 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayAnyAllNonePredicates",
            expected: "true\ntrue\ntrue\n"
        )
    }

    @Test
    func testCodegenArrayAnyAllNoneWithCapturingPredicateAndEmptyReceiver() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3, 4, 5)
            val threshold = 3
            println(arr.any { it == threshold })
            println(arr.all { it < threshold })

            val empty = arrayOf<Int>()
            println(empty.any { it > 0 })
            println(empty.all { it > 0 })
            println(empty.none { it > 0 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayAnyAllNoneCapturingAndEmpty",
            expected:
                """
                true
                false
                false
                true
                true
                """ + "\n"
        )
    }

}
#endif
