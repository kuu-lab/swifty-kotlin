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
struct CodegenBackendShortCircuitLogicalOperatorsTests {

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
    func testCodegenLogicalOrShortCircuitsWhenLhsIsTrue() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = true || sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalOrShortCircuitTrue", expected: "result=true\n")
    }

    @Test
    func testCodegenLogicalAndShortCircuitsWhenLhsIsFalse() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = false && sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndShortCircuitFalse", expected: "result=false\n")
    }

    @Test
    func testCodegenLogicalOrEvaluatesRhsWhenLhsIsFalse() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return true
        }

        fun main() {
            val result = false || sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LogicalOrEvaluatesRhsWhenNeeded",
            expected: "SIDE EFFECT EVALUATED\nresult=true\n"
        )
    }

    @Test
    func testCodegenLogicalAndEvaluatesRhsWhenLhsIsTrue() throws {
        let source = """
        fun sideEffect(): Boolean {
            println("SIDE EFFECT EVALUATED")
            return false
        }

        fun main() {
            val result = true && sideEffect()
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LogicalAndEvaluatesRhsWhenNeeded",
            expected: "SIDE EFFECT EVALUATED\nresult=false\n"
        )
    }

    // Regression test: `list.isEmpty() || list.last() == x` must not evaluate
    // `list.last()` when the list is already empty, or it throws NoSuchElementException.
    @Test
    func testCodegenLogicalOrShortCircuitAvoidsNoSuchElementException() throws {
        let source = """
        fun main() {
            val stack = mutableListOf<String>()
            val result = stack.isEmpty() || stack.last() == ".."
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalOrAvoidsListLastCrash", expected: "result=true\n")
    }

    // Regression test: `s.length >= 2 && s[1] == x` must not evaluate `s[1]`
    // when the length guard already fails, or it throws an out-of-bounds exception.
    @Test
    func testCodegenLogicalAndShortCircuitAvoidsStringIndexOutOfBounds() throws {
        let source = """
        fun main() {
            val s = "a"
            val result = s.length >= 2 && s[1] == ':'
            println("result=$result")
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndAvoidsStringIndexCrash", expected: "result=false\n")
    }

    @Test
    func testCodegenChainedLogicalAndShortCircuitsAtFirstFalse() throws {
        let source = """
        fun t(tag: String): Boolean { println("eval $tag"); return true }
        fun f(tag: String): Boolean { println("eval $tag"); return false }

        fun main() {
            val result = t("a") && f("b") && t("c")
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ChainedLogicalAndShortCircuit",
            expected: "eval a\neval b\nresult=false\n"
        )
    }

    @Test
    func testCodegenChainedLogicalOrShortCircuitsAtFirstTrue() throws {
        let source = """
        fun t(tag: String): Boolean { println("eval $tag"); return true }
        fun f(tag: String): Boolean { println("eval $tag"); return false }

        fun main() {
            val result = f("a") || t("b") || t("c")
            println("result=$result")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ChainedLogicalOrShortCircuit",
            expected: "eval a\neval b\nresult=true\n"
        )
    }

    @Test
    func testCodegenLogicalAndInIfConditionKeepsSmartCastAndShortCircuits() throws {
        let source = """
        fun main() {
            val s: String? = null
            if (s != null && s.length > 0) {
                println("non-empty")
            } else {
                println("null-or-empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "LogicalAndInIfConditionSmartCast", expected: "null-or-empty\n")
    }
}
#endif
