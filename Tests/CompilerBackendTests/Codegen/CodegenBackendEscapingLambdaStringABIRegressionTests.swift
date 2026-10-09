@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendEscapingLambdaStringABIRegressionTests {

    @Test
    func testLambdaReturnedFromIfExpressionBodyRegression() throws {
        let source = """
        fun retLambda(flag: Boolean): (String) -> String =
            if (flag) ({ s -> s.uppercase() }) else ({ s -> s.lowercase() })
        fun plain(): (String) -> String = { s -> s + "!" }

        fun main() {
            println(retLambda(true)("Ab"))
            println(retLambda(false)("Ab"))
            println(plain()("x"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LambdaReturnedFromIfExprBody",
            expected: "AB\nab\nx!\n"
        )
    }

    /// `{ params -> ... }` as an if/when branch body is a function literal, not
    /// a block.
    @Test
    func testBraceLambdaLiteralAsIfAndWhenBranchRegression() throws {
        let source = """
        fun retLambda(flag: Boolean): (String) -> String = if (flag) { s -> s.uppercase() } else { s -> s.lowercase() }
        fun pick(flag: Boolean): (Int) -> Int = when (flag) { true -> { x -> x + 1 }; false -> { x -> x - 1 } }

        fun main() {
            println(retLambda(true)("Ab"))
            println(retLambda(false)("Ab"))
            println(pick(true)(10))
            println(pick(false)(10))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BraceLambdaBranchLiteral",
            expected: "AB\nab\n11\n9\n"
        )
    }
}
#endif
