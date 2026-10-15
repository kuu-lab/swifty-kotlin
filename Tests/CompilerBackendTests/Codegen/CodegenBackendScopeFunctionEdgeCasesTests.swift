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

    @Test
    func testCodegenCompilesNamedContextParametersAndAccessors() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        var seen = ""

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        fun render(value: String): String = prefix + value

        @OptIn(ExperimentalContextParameters::class)
        context(index: Int)
        fun selected(values: Array<String>): String = values[index]

        @OptIn(ExperimentalContextParameters::class)
        context(prefix: String)
        var current: String
            get() = prefix
            set(value) { seen = prefix + value }

        class ContextHolder {
            @OptIn(ExperimentalContextParameters::class)
            context(prefix: String)
            fun render(value: String): String = prefix + value

            @OptIn(ExperimentalContextParameters::class)
            context(prefix: String)
            var current: String
                get() = prefix
                set(value) { seen = prefix + value }
        }

        @OptIn(ExperimentalContextParameters::class)
        fun main() {
            context(prefix: String)
            fun localRender(value: String): String = prefix + value

            println(context("I") { render("K") })
            println(context(1) { selected(arrayOf("A", "B")) })
            println(context("L") { localRender("K") })
            val renderRef: context(String) (String) -> String = ::render
            println(context("C") { renderRef("K") })
            val holder = ContextHolder()
            println(context("M") { holder.render("K") })
            context("O") {
                current = "K"
                println(current)
                println(seen)
            }
            context("P") {
                holder.current = "K"
                println(holder.current)
                println(seen)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "NamedContextParameters",
                emit: .executable,
                outputPath: outputBase
            )
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                ==
                """
                IK
                B
                LK
                CK
                MK
                O
                OK
                P
                PK
                """
                + "\n"
            )
        }
    }
}
#endif
