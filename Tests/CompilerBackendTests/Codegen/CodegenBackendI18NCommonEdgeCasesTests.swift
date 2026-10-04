#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendI18NCommonEdgeCasesTests {

    @Test
    func testCodegenCompilesI18NCommonEdgeCases() throws {
        let source = """
        import java.util.Locale

        fun main() {
            println("%s:%d".format("age", 7))
            println("%.1f".format(3.5))

            println("Hello".uppercase())
            println("Hello".lowercase())
            println("I".lowercase(Locale("tr")))
            println("i".uppercase(Locale("tr")))

            val locale = Locale("en", "US")
            println("HELLO".lowercase(locale))
            println("hello".uppercase(locale))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "I18NCommonEdgeCases",
            expected:
                """
                age:7
                3.5
                HELLO
                hello
                \u{131}
                \u{130}
                hello
                HELLO
                """ + "\n"
        )
    }

}
#endif
