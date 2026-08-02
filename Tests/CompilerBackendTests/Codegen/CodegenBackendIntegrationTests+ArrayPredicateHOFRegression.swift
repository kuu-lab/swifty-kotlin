@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// BUG-164 regression: `Array<T>.any`/`all`/`none` with a predicate have real,
// `inline` Kotlin-source declarations (Stdlib/kotlin/collections/ArrayAnyNoneHOF.kt)
// that take the predicate as an ordinary inline-callable parameter. But
// CallLowerer+LegacyMemberLikeCalls.swift's isConcreteArrayLikeType special
// case unconditionally intercepted these calls and emitted a direct native
// kk_array_any/all/none call with the raw, un-adapted lambda argument instead
// of letting the real inline declaration run — a different calling convention
// than the closure-adapted (fnPtr, closureRaw) pair those native bridges
// expect. The compiled lambda body was then invoked with the wrong argument
// shape and crashed (EXC_BAD_ACCESS) reading its own parameter. List's `any`
// has no competing source declaration and was unaffected, which is why this
// was Array-receiver-specific. Fixed by skipping the native-bridge shortcut
// for `any`/`all`/`none` whenever Sema already resolved a real, source-backed
// (declSite != nil) callee, falling through to the normal call-lowering path
// that inlines the real declaration like any other user-written inline call.
extension CodegenBackendIntegrationTests {
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
