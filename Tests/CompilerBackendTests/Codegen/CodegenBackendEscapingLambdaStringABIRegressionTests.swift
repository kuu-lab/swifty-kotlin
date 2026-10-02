@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendEscapingLambdaStringABIRegressionTests {

    /// A non-capturing lambda is a bare `symbolRef`. Invoked through
    /// `kk_function_invoke_*` it must use the flat intptr callback ABI, which
    /// differs from the natural Kotlin ABI when the lambda takes or returns a
    /// `String`. The lambda used to keep the natural ABI whenever the
    /// `symbolRef` reached the invoke via `!!`, a local alias, an if/when
    /// merge copy or a `return`, so the call read the wrong register (null) or
    /// crashed.
    @Test
    func testNullableStringFunctionBangCallRegression() throws {
        let source = """
        fun main() {
            val nf2: (() -> String)? = { "s" }
            println(nf2!!())
            val nf4: ((String) -> String)? = { it + "!" }
            println(nf4!!("a"))
            val nf: (() -> String)? = { "s" }
            val f = nf!!
            println(f())
            val ni: (() -> Int)? = { 7 }
            println(ni!!())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NullableStringFunctionBangCall",
            expected: "s\na!\ns\n7\n"
        )
    }

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
