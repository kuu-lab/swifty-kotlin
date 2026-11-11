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
            }
            """, expected: "value\nempty\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
