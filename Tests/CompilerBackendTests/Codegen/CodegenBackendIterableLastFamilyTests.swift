#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendIterableLastFamilyTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    @Test
    func testCodegenIterableLastFamilyMatchesKotlinSemantics() throws {
        let source = """
        fun main() {
            val values: Iterable<Int> = listOf(1, 2, 2, 4)
            println(values.last())
            println(values.last { it % 2 == 0 })
            println(values.lastIndexOf(2))
            println(values.lastOrNull())
            println(values.lastOrNull { it > 10 } ?: -1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try pipelineHelper.runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableLastFamily",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(output == "4\n4\n2\n4\n-1\n")
        }
    }

    @Test
    func testCodegenIterableLastFamilyUsesBundledSourceCalls() throws {
        let source = """
        fun render(values: Iterable<Int>, element: Int): Int {
            values.last()
            values.last { it > 0 }
            values.lastIndexOf(element)
            values.lastOrNull()
            return values.lastOrNull { it > 0 } ?: -1
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "IterableLastFamilyKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(containsKotlinCallee("last", in: callees))
            #expect(containsKotlinCallee("lastIndexOf", in: callees))
            #expect(containsKotlinCallee("lastOrNull", in: callees))
            #expect(!callees.contains("__kk_iterable_last"))
        }
    }
}
#endif
