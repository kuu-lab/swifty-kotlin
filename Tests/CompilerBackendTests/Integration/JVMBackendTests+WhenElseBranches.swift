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
            }
            fun main() {
                println(blockThenElse(1))
                println(blockThenElse(2))
                println(booleanThenElse(true))
                println(booleanThenElse(false))
                println(expressionThenElse(1))
                println(expressionThenElse(2))
                ifBodyThenElse(1)
                ifBodyThenElse(2)
                assignmentBodies()
            }
            """, expected: "one\nother\ntrue\nfalse\none\nother\npositive\nfallback\n20\n30\n20\n", mode: mode, root: root)
        }
    }
}
#endif
