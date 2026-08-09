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
struct CodegenBackendCollectionIndexLookupTests {
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

    @Test func testCodegenListIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 10)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(30))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexOfRuntime", expected: "0\n1\n-1\n")
    }

    @Test func testCodegenListOfCharIndexOperatorUsesListGet() throws {
        let source = """
        fun main() {
            val chars = listOf('h', 'i')
            println(chars[0])
            println(chars[1])
            // A List<Char> obtained via String.toList() must behave the same.
            println("hi".toList()[0])
            // The member forms already worked and must keep working alongside the operator.
            println(chars.get(0))
            println(chars.first())
            println(chars.last())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListOfCharIndexOperator", expected: "h\ni\nh\nh\nh\ni\n")
    }

    @Test func testCodegenStringIndexOperatorUsesStringGet() throws {
        let source = """
        fun main() {
            val s = "hello"
            println(s[0])
            println(s[4])
        }
        """

        try assertKotlinOutput(source, moduleName: "StringIndexOperator", expected: "h\no\n")
    }
}
#endif
