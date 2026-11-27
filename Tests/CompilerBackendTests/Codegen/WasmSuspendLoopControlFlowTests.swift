@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct WasmSuspendLoopControlFlowTests {
    @Test
    func emitsSuspendJoinAllLoop() throws {
        let source = """
        class Job {
            suspend fun join() {}
        }

        class JobIterator {
            operator fun hasNext(): Boolean = false
            operator fun next(): Job = Job()
        }

        class JobCollection {
            operator fun iterator(): JobIterator = JobIterator()
        }

        suspend fun JobCollection.joinAll() {
            val jobs = this
            for (job in jobs) {
                job.join()
            }
        }

        fun main() {}
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("wasm-suspend-join-all-\(UUID().uuidString)")
                .path
            let wasmPath = outputPath + ".wasm"
            defer { try? FileManager.default.removeItem(atPath: wasmPath) }
            let options = CompilerOptions(
                moduleName: "WasmSuspendJoinAll",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: .wasmWASI,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            let context = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToLowering(context)
            try CodegenPhase().run(context)
            try assertNoDiagnosticErrors(context)

            let wasm = try Data(contentsOf: URL(fileURLWithPath: wasmPath))
            #expect(Array(wasm.prefix(8)) == [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00])
            if let execution = try WasmCodegenTests().runUnderNode(Array(wasm)) {
                #expect(execution.status == 0)
            }
        }
    }
}
