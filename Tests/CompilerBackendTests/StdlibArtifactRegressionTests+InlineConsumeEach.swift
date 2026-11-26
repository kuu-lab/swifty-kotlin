@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testConsumeEachLambdaSuspendsAndReturnsNonLocally() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*

        suspend fun relay(input: Channel<Int>, output: Channel<Int>): Int {
            var last: Int? = null
            input.consumeEach {
                if (it < 0) return last ?: -1
                output.send(it * 10)
                last = it
            }
            return last ?: 0
        }

        fun main() = runBlocking {
            val input = Channel<Int>(10)
            val output = Channel<Int>(10)
            input.send(1)
            input.send(2)
            input.send(-1)
            println(relay(input, output))
            println(output.receive())
            println(output.receive())
            println(input.isClosedForReceive)

            val single = Channel<Int>(10)
            single.send(5)
            single.close()
            launch {
                single.consumeEach {
                    if (it == 5) return@launch
                    println("unreached element")
                }
                println("unreached after loop")
            }.join()
            println("done")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "InlineConsumeEach",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "2\n10\n20\ntrue\ndone\n")
        }
    }
}
