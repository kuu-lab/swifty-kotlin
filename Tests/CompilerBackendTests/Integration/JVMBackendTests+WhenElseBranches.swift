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
            fun main() {
                println(blockThenElse(1))
                println(blockThenElse(2))
                println(booleanThenElse(true))
                println(booleanThenElse(false))
                println(expressionThenElse(1))
                println(expressionThenElse(2))
                ifBodyThenElse(1)
                ifBodyThenElse(2)
            }
            """, expected: "one\nother\ntrue\nfalse\none\nother\npositive\nfallback\n", mode: mode, root: root)
        }
    }
}
#endif
