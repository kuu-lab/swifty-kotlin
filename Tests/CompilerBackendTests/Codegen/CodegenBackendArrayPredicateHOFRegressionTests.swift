#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// BUG-164 regression: `Array<T>.any`/`all`/`none` with a predicate have real,
// `inline` Kotlin-source declarations (Stdlib/kotlin/collections/ArrayAnyNoneHOF.kt)
// that take the predicate as an ordinary inline-callable parameter. But
// CallLowerer+LegacyMemberLikeCalls.swift's old array bridge shortcut emitted a
// direct native kk_array_any/all/none call with the raw, un-adapted lambda
// argument instead of letting the source declaration run. The compiled lambda
// body was then invoked with the wrong argument shape and crashed. The runtime
// bridge path is removed; this test keeps the source-backed call behavior fixed.
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
