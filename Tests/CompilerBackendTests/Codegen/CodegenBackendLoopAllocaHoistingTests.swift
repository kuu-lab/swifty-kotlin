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
struct CodegenBackendLoopAllocaHoistingTests {

    @Test
    func testCodegenHoistsLoopBodyAllocasIntoEntryBlock() throws {
        let source = """
        class Counter {
            var value: Int = 0
            fun bump(): Int {
                value += 1
                return value
            }
        }

        fun main() {
            val counter = Counter()
            var total = 0
            for (i in 1..3) {
                total += counter.bump()
                total += "value=${counter.value}".length
            }
            println(total)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let llvmBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let llvmCtx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LoopAllocaHoisting",
                emit: .llvmIR,
                outputPath: llvmBase
            )
            let llvmPath = try #require(llvmCtx.generatedLLVMIRPath)
            let ir = try String(contentsOfFile: llvmPath, encoding: .utf8)

            var blocksInCurrentFunction = 0
            var allocasOutsideEntry: [String] = []
            for line in ir.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("define ") {
                    blocksInCurrentFunction = 0
                } else if line.hasSuffix(":"), !line.hasPrefix(" ") {
                    blocksInCurrentFunction += 1
                } else if line.contains(" = alloca "), blocksInCurrentFunction > 1 {
                    allocasOutsideEntry.append(String(line))
                }
            }

            #expect(
                allocasOutsideEntry.isEmpty,
                "allocas must stay in the entry block, found: \(allocasOutsideEntry)"
            )
        }
    }
}
#endif
