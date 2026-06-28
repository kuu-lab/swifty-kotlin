@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesI18NCommonEdgeCases() throws {
        let source = """
        import java.util.Locale

        fun main() {
            println("%s:%d".format("age", 7))
            println("%.1f".format(3.5))

            println("Hello".uppercase())
            println("Hello".lowercase())

            val locale = Locale("en", "US")
            println(locale.language)
            println(locale.country)
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
                en
                US
                """ + "\n"
        )
    }
}

