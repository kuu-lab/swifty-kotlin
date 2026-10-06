#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendStringSurrogateEscapeTests {
    @Test
    func testConsoleOutputReplacesIsolatedSurrogates() throws {
        let source = """
        fun main() {
            val star = "🌟"
            println(star.first())
            println("hello🌟".lastOrNull())
            val boxed: Any = star.last()
            println(boxed)
            println(star.last().toString().first().code)
            println("x" + star.last() + "y")
            println(star)
            println("�")
            print(star.last())
            println("!")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ConsoleSurrogate",
            expected: "?\n?\n?\n57119\nx?y\n🌟\n�\n?!\n"
        )
    }

    @Test
    func testStringLiteralPreservesIsolatedSurrogateEscapesAsUTF16CodeUnits() throws {
        let source = """
        fun main() {
            println("\\uD83D".length)
            println("\\uD83D".first().code)
            println(("\\uD83D" + "\\uDE00").length)
            println("x\\uD83Dy".length)
            println("\\uDC00".length)
            println("\\uDC00".first().code)
            println("\\uD83D\\uDE00".length)
            println("\\uD83D\\uDE00" == "😀")
            println("\\uFFFF".first().code)
            println('\\uD83D'.code)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringSurrogateEscape",
            expected: "1\n55357\n2\n3\n1\n56320\n2\ntrue\n65535\n55357\n"
        )
    }
}
#endif
