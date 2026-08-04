@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

// DEBT-KIR-005: `for (x in array)` silently never executed the loop body
// because arrays have no real `iterator()` member for Sema to bind, so
// lowering fell through to the range-iterator intrinsics and misread the
// array object as a range (hasNext() always false).
@Suite
struct CodegenBackendArrayForLoopIterationTests {

    @Test
    func testByteArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (b in "HI".encodeToByteArray()) {
                println(b)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ByteArrayForLoopIteration", expected: "72\n73\n")
    }

    @Test
    func testIntArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (x in intArrayOf(10, 20, 30)) {
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "IntArrayForLoopIteration", expected: "10\n20\n30\n")
    }

    @Test
    func testObjectArrayForLoopIteration() throws {
        let source = """
        fun main() {
            for (s in arrayOf("a", "b", "c")) {
                println(s)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ObjectArrayForLoopIteration", expected: "a\nb\nc\n")
    }

    @Test
    func testEmptyArrayForLoopDoesNotExecuteBody() throws {
        let source = """
        fun main() {
            for (x in IntArray(0)) {
                println(x)
            }
            println("done")
        }
        """
        try assertKotlinOutput(source, moduleName: "EmptyArrayForLoopDoesNotExecuteBody", expected: "done\n")
    }

    @Test
    func testArrayForLoopContinueAndBreak() throws {
        let source = """
        fun main() {
            for (x in intArrayOf(1, 2, 3, 4, 5)) {
                if (x == 2) continue
                if (x == 4) break
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "ArrayForLoopContinueAndBreak", expected: "1\n3\n")
    }

    @Test
    func testByteArrayForLoopLowersToIndexBasedLoopNotRangeIterator() throws {
        let source = """
        fun main() {
            for (b in "HI".encodeToByteArray()) {
                println(b)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("kk_array_size"), "array for-loop should call kk_array_size, got: \(callees)")
        #expect(
            callees.contains("kk_array_get_inbounds"),
            "array for-loop should call kk_array_get_inbounds, got: \(callees)"
        )
        #expect(!callees.contains("kk_range_iterator"), "array for-loop must not use kk_range_iterator, got: \(callees)")
        #expect(!callees.contains("kk_range_hasNext"), "array for-loop must not use kk_range_hasNext, got: \(callees)")
        #expect(!callees.contains("kk_range_next"), "array for-loop must not use kk_range_next, got: \(callees)")
    }
}

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
#endif
