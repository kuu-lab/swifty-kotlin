import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testFunctionNNominalTypesCompileAndRun(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class Increment : Function1<Int, Int> {
                override fun invoke(value: Int): Int = value + 1
            }

            class Constant : Function0<Int> {
                override fun invoke(): Int = 42
                fun callSelf(): Int = this()
            }

            fun main() {
                val simple: Function1<Int, Int> = { it + 1 }
                val qualified: kotlin.Function1<Int, Int> = simple
                val implementation: Function1<Int, Int> = Increment()
                println(simple(1))
                println(qualified(2))
                println(implementation(3))
                println(Constant().callSelf())
            }
            """,
            expectedOutput: "2\n3\n4\n42\n",
            moduleName: "KUU3580FunctionNNominalTypes",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// KUU-3578: named FunctionN checks and function-type subclasses work above arity 22.
    @Test(arguments: [false, true])
    func testFunctionNNominalTypesBeyond22CompileAndRun(allowDefaultStdlibLibrary: Bool) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scripts/diff_cases/kuu_3578_functionn_over_22.kt"
            ),
            encoding: .utf8
        )

        try compileAndRunKotlin(
            source,
            expectedOutput: "true\nfalse\nfalse\nOK\n",
            moduleName: "KUU3578FunctionNNominalTypesBeyond22",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
