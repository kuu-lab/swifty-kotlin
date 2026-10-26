@testable import CompilerCore
import Testing

@Suite(.serialized)
struct WhenCallableReferenceInvocationExecutionTests {
    @Test
    func immediatelyInvokesStringReferenceSelectedFromWhen() throws {
        try compileAndRunKotlin(
            """
            fun decodeValue(value: String): Any {
                return when (value[0]) {
                    'F' -> String::toFloat
                    'I' -> String::toInt
                    else -> throw IllegalArgumentException("x")
                }(value.substring(2))
            }

            fun main() {
                println(decodeValue("I:42"))
                println(decodeValue("F:42"))
            }
            """,
            expectedOutput: "42\n42.0\n",
            moduleName: "KUU3392WhenCallableReferenceInvocation",
            requireNoCompilerDiagnostics: true
        )
    }
}
