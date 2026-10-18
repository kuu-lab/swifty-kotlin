@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU2122SuspendLambdaCaptureTests {
    @Test(arguments: [0, 2])
    func inlinedSuspendLambdaSeesOriginalCoroutineContext(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2122_coroutine_context_inline_lambda.kt", file: #filePath),
            expectedOutput: "DIRECT OK\nOK\nOK\n",
            moduleName: "KUU2122CoroutineContextInlineLambda",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func crossInlineCapturedReceiverDispatchesAcrossSourceFiles(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlinSources(
            [
                """
                interface Consumer { fun consume(s: String) }

                inline fun crossInlineBuilderConsumer(crossinline block: (String) -> Unit) =
                    object : Consumer {
                        override fun consume(s: String) { block(s) }
                    }

                class Container {
                    var value = "FAIL"
                    val consumer = crossInlineBuilderConsumer { value = it }
                }
                """,
                """
                fun main() {
                    val container = Container()
                    container.consumer.consume("OK")
                    println(container.value)
                }
                """,
            ],
            expectedOutput: "OK\n",
            moduleName: "KUU2122CrossInlineCapturedReceiver",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
