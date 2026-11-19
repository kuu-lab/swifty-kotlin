#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11WhenEntriesMayBeAdjacentToElse(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun blockThenElse(x: Int): String = when (x) {
                1 -> {
                    "one"
                } else -> {
                    "other"
                }
            }
            fun booleanThenElse(flag: Boolean): Boolean = when (flag) {
                true -> {
                    true
                } else -> false
            }
            fun expressionThenElse(x: Int): String = when (x) {
                1 -> "one" else -> "other"
            }
            fun expressionIfThenElse(x: Int): Int = when (x) {
                1 -> if (x > 0) 10 else 20 else -> 30
            }
            fun ifBodyThenElse(x: Int) {
                when (x) {
                    1 -> if (x > 0) {
                        println("positive")
                    }
                    else -> {
                        println("fallback")
                    }
                }
            }
            fun assignmentBodies() {
                var result = 0
                when (2) {
                    1 -> result = 10 else -> result = 20
                }
                println(result)
                when (2) {
                    1 -> result = 10 2 -> result = 30 else -> result = 40
                }
                println(result)
                var compound = 0
                when (2) {
                    1 -> compound += 10 2 -> compound += 20 else -> compound += 30
                }
                println(compound)
                var ifValue = 0
                when (1) {
                    1 -> ifValue = if (1 > 0) 10 else 20 else -> ifValue = 40
                }
                println(ifValue)
                when (2) {
                    1 -> ifValue = if (1 > 0) 10 else 20 else -> ifValue = 40
                }
                println(ifValue)
            }
            fun expressionBeforeAssignmentEntry() {
                var x = 0
                var y = 0
                when (2) {
                    1 -> x 2 -> y = 30 else -> y = 40
                }
                println(x)
                println(y)
            }
            fun main() {
                println(blockThenElse(1))
                println(blockThenElse(2))
                println(booleanThenElse(true))
                println(booleanThenElse(false))
                println(expressionThenElse(1))
                println(expressionThenElse(2))
                println(expressionIfThenElse(1))
                println(expressionIfThenElse(2))
                ifBodyThenElse(1)
                ifBodyThenElse(2)
                assignmentBodies()
                expressionBeforeAssignmentEntry()
            }
            """, expected: "one\nother\ntrue\nfalse\none\nother\n10\n30\npositive\nfallback\n20\n30\n20\n10\n40\n0\n30\n", mode: mode, root: root)
        }
    }
}
#endif
