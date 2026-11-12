#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11WhenGuardsNarrowTypesAndFallThroughInOrder(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            var trace = ""
            fun guardLength(length: Int): Boolean {
                trace += "guard:$length;"
                return length > 1
            }
            fun markBody(label: String): String {
                trace += "body:$label;"
                return label
            }
            fun choose(value: Any): String = when (value) {
                is String if guardLength(value.length) -> markBody("long")
                is String -> markBody("short")
                else -> markBody("other")
            }
            fun guardedElse(value: Any): String = when (value) {
                is Int -> "int"
                else if value is String -> "string"
                else -> "other"
            }
            fun main() {
                println("${choose("abc")}:$trace")
                trace = ""
                println("${choose("a")}:$trace")
                trace = ""
                println("${choose(1)}:$trace")
                println(guardedElse("x"))
                println(guardedElse(1))
                println(guardedElse(1.5))
            }
            """, expected: "long:guard:3;body:long;\nshort:guard:1;body:short;\nother:body:other;\nstring\nint\nother\n", mode: mode, root: root)
        }
    }
}
#endif
