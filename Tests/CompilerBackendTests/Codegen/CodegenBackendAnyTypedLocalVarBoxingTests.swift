#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendAnyTypedLocalVarBoxingTests {

    @Test
    func testAnyAndNumberTypedLocalsAreBoxedCorrectly() throws {
        try assertKotlinOutput(
            """
            fun main() {
                var i: Any = 42
                i = 99L
                println(i is Long)
                println(i is Int)
                println(i)
            }
            """,
            moduleName: "AnyTypedLocalVarReassignment",
            expected: "true\nfalse\n99\n"
        )

        try assertKotlinOutput(
            """
            fun main() {
                val i: Any = 42
                println(i is Int)
                println(i is Long)
            }
            """,
            moduleName: "AnyTypedLocalValWithoutReassignment",
            expected: "true\nfalse\n"
        )

        try assertKotlinOutput(
            """
            fun main() {
                var a: Any = "hello"
                println(a is String)
                a = 42
                println(a is Int)
                println(a is String)
                a = 3.14
                println(a is Double)
                println(a is Int)
            }
            """,
            moduleName: "AnyTypedLocalVarMultipleReassignments",
            expected: "true\ntrue\nfalse\ntrue\nfalse\n"
        )

        try assertKotlinOutput(
            """
            fun main() {
                var i: Any
                i = 42
                println(i is Int)
                println(i is Long)
            }
            """,
            moduleName: "AnyTypedLocalVarWithoutInitializer",
            expected: "true\nfalse\n"
        )

        try assertKotlinOutput(
            """
            fun main() {
                var n: Number = 42
                println(n is Int)
                println(n is Long)
                n = 99L
                println(n is Long)
                println(n is Int)
                println(n)
            }
            """,
            moduleName: "NumberTypedLocalVarReassignment",
            expected: "true\nfalse\ntrue\nfalse\n99\n"
        )
    }

    @Test
    func testSmartcastedAnyLocalCompoundAssignmentsUsePrimitiveValues() throws {
        try assertKotlinOutput(
            """
            fun main() {
                var v: Any = 'C'
                if (v is Char) {
                    v++
                    println(v)
                    println(v.toInt())
                    v += 2
                    println(v)
                    println(v.toInt())
                    v--
                    println(v)
                    println(v.toInt())
                }
            }
            """,
            moduleName: "SmartcastAnyLocalCompoundAssignments",
            expected: "D\n68\nF\n70\nE\n69\n"
        )
    }
}
#endif
