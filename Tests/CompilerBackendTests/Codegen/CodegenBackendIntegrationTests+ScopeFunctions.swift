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
struct CodegenBackendScopeFunctionsTests {

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
    func testCodegenCompilesScopeFunctions() throws {
        let source = """
        class Builder {
            var x: Int = 0
            var y: Int = 0
        }

        fun main() {
            println("Hello".let { it.length })
            println("Hello".run { length })
            val built = Builder().apply {
                x = 10
                y = 20
            }
            println(built.x + built.y)
            println("Hello".also { println(it.length) }.length)
            println(with("Hello") { length })
        }
        """

        try assertKotlinOutput(source, moduleName: "ScopeFunctions", expected: "5\n5\n30\n5\n5\n5\n")
    }

    @Test
    func testCodegenCompilesStringBuilderAppendVarargInReceiverLambda() throws {
        let source = """
        fun buildGreeting(action: StringBuilder.() -> Unit): String {
            val sb = StringBuilder()
            sb.action()
            return sb.toString()
        }

        fun main() {
            val greeting = buildGreeting {
                append("Hello")
                append(", ")
                append("World!")
            }
            println(greeting)

            val result = with(StringBuilder()) {
                append("Kotlin ")
                append("is ")
                append("fun")
                toString()
            }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "StringBuilderAppendVarargReceiverLambda", expected: "Hello, World!\nKotlin is fun\n")
    }

    @Test
    func testCodegenCompilesUIntArrayConstructorIndexingAndFactory() throws {
        let source = """
        fun main() {
            val arr = UIntArray(3) { (it * 2).toUInt() }
            arr[1] = 9u
            val extra = uintArrayOf(4u, 5u)
            println(arr.size)
            println(arr[0])
            println(arr[1])
            println(arr[2])
            println(extra[0] + extra[1])
        }
        """

        try assertKotlinOutput(source, moduleName: "UIntArrayExecutable", expected: "3\n0\n9\n4\n9\n")
    }
}
#endif
