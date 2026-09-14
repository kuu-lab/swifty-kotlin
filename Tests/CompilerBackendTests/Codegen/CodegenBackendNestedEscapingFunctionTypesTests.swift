@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNestedEscapingFunctionTypesTests {
    @Test
    func codegenNestedEscapingFunctionTypeBooleanComparison() throws {
        let source = """
        fun main() {
            val f: (Int) -> (String) -> Boolean = { m -> { s -> s.length * m > 10 } }
            println(f(2)("hello"))
            println(f(2)("hi"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NestedEscapingFunctionTypes",
            expected:
                """
                false
                false
                """
                + "\n"
        )
    }

}

#endif
