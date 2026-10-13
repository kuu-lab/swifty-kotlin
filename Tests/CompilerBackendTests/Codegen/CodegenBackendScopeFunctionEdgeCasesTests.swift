#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendScopeFunctionEdgeCasesTests {

    @Test(arguments: [true, false])
    func testTailPositionLabeledReturnPropagatesValue(defaultStdlib: Bool) throws {
        let source = """
        fun main() {
            val r = run { return@run 9 }
            println(r)
            println(run { return@run 9 })
            println(run(foo@{ return@foo 7 }))
            println(run { return@run "tail" })
            println(run<Int?> { return@run null })
            println(run { return@run 2147483648L })
            println("x".let { return@let 4 })
            println(with(0) { return@with "w" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TailLabeledReturnValue",
            expected:
                """
                9
                9
                7
                tail
                null
                2147483648
                4
                w
                """
                + "\n",
            allowDefaultStdlibLibrary: defaultStdlib
        )
    }

    @Test
    func testCodegenCompilesContextHelper() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            val result = context("context-ok") { contextOf<String>() }
            println(result)
            println(context("context-two", 2) { contextOf<String>() })
            println(context(1, 2, "context-six", 4, 5, 6) { contextOf<String>() })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ContextHelper",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                ==
                """
                context-ok
                context-two
                context-six
                """
                + "\n"
            )
        }
    }
}
#endif
