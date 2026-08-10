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
struct CodegenBackendPrimitiveAutoboxingInMutableCollectionsTests {

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
    func testPrimitiveArgumentBoxedWhenAddedToMutableCollections() throws {
        let source = """
        fun main() {
            // Reported bug: literal-built list seeds boxed Chars, add('d') must match.
            val chars = mutableListOf('a', 'b', 'c')
            chars.add('d')
            println(chars)

            // Generalization: an empty MutableList<Char>.
            val fresh = mutableListOf<Char>()
            fresh.add('x')
            fresh.add('y')
            println(fresh)

            // add(index, element) insertion.
            val ins = mutableListOf('a', 'c')
            ins.add(1, 'b')
            println(ins)

            // set(index, element) via indexed assignment.
            val seq = mutableListOf('a', 'b', 'c')
            seq[1] = 'z'
            println(seq)

            // MutableSet.add(Char).
            val set = mutableSetOf<Char>()
            set.add('m')
            println(set)

            // Boolean elements must render as true/false, not 0/1.
            val flags = mutableListOf<Boolean>()
            flags.add(true)
            flags.add(false)
            println(flags)

            // Double elements must render as their value, not the raw bit pattern.
            val reals = mutableListOf<Double>()
            reals.add(1.5)
            println(reals)

            // Regression: Int elements still render as their decimal value.
            val nums = mutableListOf<Int>()
            nums.add(100)
            println(nums)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAutoboxingInMutableCollections",
            expected:
                """
                [a, b, c, d]
                [x, y]
                [a, b, c]
                [a, z, c]
                [m]
                [true, false]
                [1.5]
                [100]
                """
                + "\n"
        )
    }
}
#endif
