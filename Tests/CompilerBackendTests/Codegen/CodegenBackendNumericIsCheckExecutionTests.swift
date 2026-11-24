#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendNumericIsCheckExecutionTests {

    @Test
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

    @Test
    func testCodegenIsCheckDistinguishesConcretePrimitiveTypesWithoutAny() throws {
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

    @Test
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

    @Test
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

    @Test
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
#endif
