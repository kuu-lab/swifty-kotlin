@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct WasmSuspendLoopControlFlowTests {
    @Test
    func emitsSuspendJoinAllAndRunsDispatcherRangeLoop() throws {
        let source = """
        class Job {
            suspend fun join() {}
        }

        class JobIterator {
            private var index = 0

            operator fun hasNext(): Boolean = index < 3

            operator fun next(): Job {
                index += 1
                return Job()
            }
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

        fun retry(): Boolean = false

        fun main(): Int {
            var visited = 0
            for (job in JobCollection()) {
                visited += 1
            }

            var last = 0
            for (i in 1..3) {
                last = i
            }

            do {
                if (retry()) continue
            } while (if (retry()) continue else false)

            return last * 10 + visited
        }
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
            if let execution = try runExportedMainUnderNode(Array(wasm)) {
                #expect(execution.status == 0)
                #expect(execution.stdout == "33\n")
            }
        }
    }

    private func runExportedMainUnderNode(
        _ bytes: [UInt8]
    ) throws -> (stdout: String, stderr: String, status: Int32)? {
        guard let node = WasmCodegenTests().nodePath() else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wasm-suspend-join-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wasmPath = dir.appendingPathComponent("test.wasm").path
        let runnerPath = dir.appendingPathComponent("run.mjs").path
        try Data(bytes).write(to: URL(fileURLWithPath: wasmPath))
        let runner = """
        import { WASI } from "node:wasi";
        import fs from "node:fs";
        const wasi = new WASI({ version: "preview1", args: [], env: {}, returnOnExit: true });
        const { instance } = await WebAssembly.instantiate(
          fs.readFileSync(process.argv[2]),
          { wasi_snapshot_preview1: wasi.wasiImport }
        );
        console.log(instance.exports.main().toString());
        """
        try runner.write(toFile: runnerPath, atomically: true, encoding: .utf8)

        let result = try CommandRunner.run(
            executable: node,
            arguments: [runnerPath, wasmPath],
            timeout: 10
        )
        return (result.stdout, result.stderr, result.exitCode)
    }
}
