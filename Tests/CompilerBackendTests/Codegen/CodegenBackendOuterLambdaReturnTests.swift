@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendOuterLambdaReturnTests {
    @Test(arguments: [true, false])
    func outerLambdaReturnsPreserveDestinationAndCleanup(defaultStdlib: Bool) throws {
        let source = """
        inline fun <T> evaluate(action: () -> T): T = action()
        fun plain(action: () -> Int): Int = action()
        fun main() {
            println(evaluate<Int> outer@{
                evaluate<Int> { return@outer 377 }
                println("unreachable")
                0
            })
            println(evaluate outer@{
                evaluate { return@outer 378 }
            })
            println(evaluate<String> outer@{
                evaluate<Int> { return@outer "outer" }
                "unreachable"
            })
            println(evaluate<Int> outer@{
                try {
                    evaluate<Int> {
                        try {
                            return@outer 379
                        } finally {
                            println("inner-finally")
                        }
                    }
                    0
                } finally {
                    println("outer-finally")
                }
            })
            evaluate<Unit> outer@{
                evaluate<Unit> { return@outer }
                println("unreachable-unit")
            }
            println(evaluate<Int> outer@{
                val inner = evaluate<Int> outer@{ return@outer 7 }
                inner + 1
            })
            println(run outer@{
                run { return@outer 380L }
                0L
            })
            println(run<Int?> outer@{
                run { return@outer null }
                0
            })
            println(evaluate<Int> outer@{
                val first = evaluate<Int> {
                    if (false) return@outer 381
                    9
                }
                first + 1
            })
            try {
                println(evaluate<Int> outer@{
                    evaluate<Int> { return@outer 382 }
                    0
                })
                println("after")
            } finally {
                println("caller-finally")
            }
            println(plain outer@{
                evaluate<Int> { return@outer 383 }
                0
            })
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "OuterLambdaReturn",
            expected: "377\n378\nouter\ninner-finally\nouter-finally\n379\n8\n380\nnull\n10\n382\nafter\ncaller-finally\n383\ndone\n",
            allowDefaultStdlibLibrary: defaultStdlib
        )
    }
}
