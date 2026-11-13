#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func multilineElvisAfterTrailingLambda() throws {
        try withWorkspace { root in
            try runM11("""
            fun parse(input: String): String =
                input.takeIf { it.isNotEmpty() }
                    ?: "empty"

            fun main() {
                println(parse("value"))
                println(parse(""))
                val filter: (String, (String) -> Boolean) -> String? = String::takeIf
                println(filter("reference") { it.isNotEmpty() })
                println(filter("reference") { it.isEmpty() })
            }
            """, expected: "value\nempty\nreference\nnull\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
