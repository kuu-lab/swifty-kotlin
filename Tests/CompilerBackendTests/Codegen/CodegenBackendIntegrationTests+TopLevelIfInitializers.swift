#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

/// BUG-165: several top-level properties initialized with a branching
/// expression used to emit duplicate basic block labels into `main`, producing
/// malformed IR that crashed LLVM during codegen.
@Suite
struct CodegenBackendTopLevelIfInitializersTests {

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
    func testCodegenMultipleBranchingTopLevelInitializersRunCorrectly() throws {
        let source = """
        val a = if (1 > 2) 1 else 2
        val b = if (1 < 2) 3 else 4
        val c = when {
            a > b -> 100
            a < b -> 200
            else -> 300
        }
        var d = if (c == 200) a * b else 0

        fun main() {
            println(a)
            println(b)
            println(c)
            if (a < b) {
                d = d + 1
            } else {
                d = d - 1
            }
            println(d)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelIfInitializersRuntime",
            expected: "2\n3\n200\n7\n"
        )
    }

    /// A `String` global holds the runtime's raw handle; reading one used to
    /// write the bridged flat aggregate back over the slot, so every later
    /// read of that property (or of the global stored next to it) saw garbage.
    @Test
    func testCodegenRepeatedStringTopLevelPropertyReadsStayValid() throws {
        let source = """
        val s = if (1 > 2) "gt" else "eq"
        val n = s.length

        fun main() {
            println(s.length)
            println(s)
            println(n)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelStringPropertyReadRuntime",
            expected: "2\neq\n2\n"
        )
    }

    /// Custom delegated `var` top-level properties route writes through a
    /// setter function, so the global slot must stay a raw string handle
    /// across the read-bridge roundtrip used for `getValue`.
    @Test
    func testCodegenStringDelegatePropertyWritesAndReadsStayValid() throws {
        let source = """
        var backing: String = "init"

        fun assignNext(value: String) {
            backing = value
        }

        class StringDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): String = backing

            operator fun setValue(thisRef: Any?, property: Any?, value: String) {
                assignNext(value)
            }
        }

        var message: String by StringDelegate()

        fun main() {
            println(message)
            message = "next"
            println(message)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelStringDelegateRuntime",
            expected: "init\nnext\n"
        )
    }
}
#endif
