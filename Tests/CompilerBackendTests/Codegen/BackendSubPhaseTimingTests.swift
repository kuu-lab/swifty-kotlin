@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite(.serialized)
struct BackendSubPhaseTimingTests {
    @Test(arguments: ["llvm", "object", "library"], [0, 2])
    func testTimingPreservesEmittedBytes(emitName: String, optValue: Int) throws {
        let emit: EmitMode = emitName == "llvm" ? .llvmIR : (emitName == "object" ? .object : .library)
        let optLevel = try #require(OptimizationLevel(rawValue: optValue))
        try withTemporaryFile(contents: "fun twice(x: Int): Int = x * 2\nfun main(): Int = twice(21)") { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent(
                emit == .library ? "output.kklib" : (emit == .llvmIR ? "output.ll" : "output.o")
            )
            var baseline: [Data]?
            for timingEnabled in [false, true] {
                let ctx = try makeContext(path: path, output: output.path, emit: emit, optLevel: optLevel)
                try runToKIR(ctx)
                try LoweringPhase().run(ctx)
                let timer = PhaseTimer()
                if timingEnabled { ctx.installPhaseTimer(timer) }
                timer.beginPhase(CodegenPhase.name)
                try CodegenPhase().run(ctx)
                timer.endPhase()
                #expect(!ctx.diagnostics.hasError)
                let artifact = emit == .library ? output.appendingPathComponent("objects/TimedBackend_0.o") : output
                var bytes = [try Data(contentsOf: artifact)]
                if emit == .library {
                    for name in ["manifest.json", "metadata.bin"] {
                        bytes.append(try Data(contentsOf: output.appendingPathComponent(name)))
                    }
                }
                if let baseline {
                    #expect(bytes == baseline)
                    let names = timer.phaseRecords[0].subRecords.map(\.name)
                    #expect(names.contains("init"))
                    #expect(names.contains("prepareMetadata"))
                    #expect(names.contains("initEmitter"))
                    #expect(names.contains("emit"))
                    #expect(names.contains("write"))
                    #expect(names.contains("opt") == (emit != .llvmIR || optLevel != .O0))
                    #expect(names.contains("writeLibraryMetadata") == (emit == .library))
                } else {
                    baseline = bytes
                    #expect(ctx.phaseTimer == nil)
                }
            }
        }
    }

    @Test
    func testExecutableRecordsLinkBreakdownAndRuns() throws {
        try withTemporaryFile(contents: "fun twice(x: Int): Int = x * 2\nfun main(): Int = twice(21)") { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("app").path
            let ctx = try makeContext(path: path, output: output, emit: .executable, optLevel: .O0)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            timer.beginPhase(CodegenPhase.name)
            try CodegenPhase().run(ctx)
            timer.endPhase()
            timer.beginPhase(LinkPhase.name)
            try LinkPhase().run(ctx)
            timer.endPhase()
            #expect(timer.phaseRecords[1].subRecords.map(\.name) == [
                "libraryObjects", "runtimeObjects", "entryWrapper", "autolinkStub", "Link/swiftc"
            ])
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.isEmpty)
        }
    }

    private func makeContext(path: String, output: String, emit: EmitMode, optLevel: OptimizationLevel) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let stdlibPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        return CompilationContext(
            options: CompilerOptions(
                moduleName: "TimedBackend", inputs: [path], outputPath: output, emit: emit,
                target: defaultTargetTriple(), optLevel: optLevel, includeStdlib: true,
                stdlibLibraryPath: stdlibPath, allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
        )
    }
}
