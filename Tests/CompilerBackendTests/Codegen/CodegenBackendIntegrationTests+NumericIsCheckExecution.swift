// Regression coverage for kk_op_is/kk_op_cast/kk_op_safe_cast when the checked
// value's runtime representation is an unboxed numeric/char primitive rather
// than a heap-boxed pointer. Prior to the fix, these callees could not
// distinguish Int/UInt/ULong/Long/Double/Float/Char from each other once
// unboxed (all reinterpret the same 64-bit word), so `is`/`as`/`as?`/`when`
// against a mismatched numeric type incorrectly reported a match.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCodegenIsCheckDistinguishesIntAndLongThroughAny() throws {
        let source = """
        fun main() {
            val i: Any = 42
            println(i is Int)
            println(i is Long)

            val l: Any = 42L
            println(l is Long)
            println(l is Int)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IsCheckDistinguishesIntAndLongThroughAny",
            expected:
                """
                true
                false
                true
                false
                """
                + "\n"
        )
    }

    func testCodegenIsCheckDistinguishesConcretePrimitiveTypesWithoutAny() throws {
        // No `Any` involved at all: the checked value's own declared type is
        // already a concrete primitive, but its KIR representation can still be
        // an unboxed literal/alias, so this must be checked independently of
        // the Any-boxing boundary.
        let source = """
        fun main() {
            val x: Int = 5
            println(x is Int)
            println(x is Long)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IsCheckDistinguishesConcretePrimitiveTypesWithoutAny",
            expected:
                """
                true
                false
                """
                + "\n"
        )
    }

    func testCodegenWhenIsBranchDistinguishesIntAndLongThroughAny() throws {
        let source = """
        fun main() {
            val i: Any = 42
            when (i) {
                is Long -> println("long")
                is Int -> println("int")
                else -> println("other")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WhenIsBranchDistinguishesIntAndLongThroughAny",
            expected: "int\n"
        )
    }

    func testCodegenSafeCastReturnsNullForMismatchedNumericType() throws {
        let source = """
        fun main() {
            val i: Any = 42
            val asLong: Long? = i as? Long
            println(asLong)
            val asInt: Int? = i as? Int
            println(asInt)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SafeCastReturnsNullForMismatchedNumericType",
            expected:
                """
                null
                42
                """
                + "\n"
        )
    }

    func testCodegenCastThrowsClassCastExceptionForMismatchedNumericType() throws {
        let source = """
        fun main() {
            val i: Any = 42
            try {
                val l = i as Long
                println("no exception: " + l)
            } catch (e: ClassCastException) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CastThrowsClassCastExceptionForMismatchedNumericType",
            expected: "caught\n"
        )
    }
}
