#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite
struct CodegenBackendPathUseLinesTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenPathUseLinesCount() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_count.txt")
            path.deleteIfExists()
            path.writeText("alpha\\nbeta\\ngamma")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesCount", expected: "3\n")
    }

    @Test
    func testCodegenPathUseLinesForEach() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_foreach.txt")
            path.deleteIfExists()
            path.writeText("one\\ntwo\\nthree")

            path.useLines { lines ->
                lines.forEach { line -> println(line) }
            }

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesForEach", expected: "one\ntwo\nthree\n")
    }

    @Test
    func testCodegenPathUseLinesEmptyFile() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_empty.txt")
            path.deleteIfExists()
            path.writeText("")

            val count = path.useLines { lines ->
                lines.count()
            }
            println(count)

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesEmpty", expected: "0\n")
    }

    @Test
    func testCodegenPathUseLinesReturnsList() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.io.path.writeText
        import kotlin.io.path.deleteIfExists

        fun main() {
            val path = Path("/tmp/kswiftk_path_uselines_tolist.txt")
            path.deleteIfExists()
            path.writeText("x\\ny\\nz")

            val lines: List<String> = path.useLines { it.toList() }
            println(lines.size)
            lines.forEach { println(it) }

            path.deleteIfExists()
        }
        """

        try assertKotlinOutput(source, moduleName: "PathUseLinesReturnsList", expected: "3\nx\ny\nz\n")
    }
}
#endif
