#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct ParallelCodegenEmissionTests {
    /// Exercises calls across partitions, overridden methods, lambdas,
    /// globals with initializers, and a file-facade `main`.
    private static let source = """
        object Singleton { val v = 3 }
        open class Base(val x: Int) { open fun describe(): Int = x }
        class Derived(x: Int) : Base(x) { override fun describe(): Int = x * 2 }
        fun add(a: Int, b: Int): Int = a + b
        fun makeLambda(): (Int) -> Int = { it * 2 }
        fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)
        fun manyArgs(a: Int, b: Int, c: Int, d: Int, e: Int): Int = a + b + c + d + e
        val topProp = 99
        var topVar = 1
        tailrec fun loop(n: Int, acc: Int): Int = if (n == 0) acc else loop(n - 1, acc + n)
        fun whenBranch(x: Int): Int = when (x) { 0 -> 10; 1 -> 20; else -> 30 }
        fun main() {
            val b = Derived(5)
            val l = makeLambda()
            topVar = add(fib(6), l(manyArgs(1, 2, 3, 4, 5))) + loop(10, 0) + whenBranch(2) + Singleton.v
        }
        """

    private func emitLLVMIR(
        inputPath: String,
        outputPath: String,
        frontendFlags: [String],
        timer: PhaseTimer? = nil
    ) throws -> String {
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ParProbe", inputs: [inputPath], outputPath: outputPath,
                emit: .llvmIR, target: TargetTriple.hostDefault(),
                frontendFlags: frontendFlags, includeStdlib: false
            ),
            sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        if let timer {
            ctx.installPhaseTimer(timer)
            timer.beginPhase("Codegen")
            try CodegenPhase().run(ctx)
            timer.endPhase()
        } else {
            try CodegenPhase().run(ctx)
        }
        let path = outputPath + ".ll"
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// `define` rows carry the module's externally visible symbols and must
    /// match serial output verbatim.
    private func defineRows(_ ir: String) -> [String] {
        ir.components(separatedBy: "\n").filter { $0.hasPrefix("define ") }.sorted()
    }

    /// Private globals can be renamed when partition modules merge
    /// (`str_lit_150` → `str_lit_150.20`), so compare their contents — the
    /// initializer rows without the symbol name — rather than the names.
    private func globalContentRows(_ ir: String) -> [String] {
        ir.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("@"),
                  let range = line.range(of: " = ")
            else { return nil }
            return String(line[range.upperBound...])
        }.sorted()
    }

    /// External functions actually invoked by the emitted code. Dead
    /// `declare` rows are not compared: LLVMLinkModules2 drops unreferenced
    /// declarations (e.g. the unconditional coroutine-root declares) that the
    /// serial module retains.
    private func calledSymbols(_ ir: String) -> [String] {
        ir.components(separatedBy: "\n").compactMap { line -> String? in
            guard let call = line.range(of: " call ") ?? line.range(of: " invoke "),
                  let at = line.range(of: "@", range: call.upperBound..<line.endIndex)
            else { return nil }
            let tail = line[at.upperBound...]
            let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            return name.isEmpty ? nil : String(name)
        }.sorted()
    }

    @Test
    func partitionedEmissionRunsAndCoversSerialDefinitions() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let timer = PhaseTimer()
            let parallelIR = try emitLLVMIR(
                inputPath: path,
                outputPath: directory.appendingPathComponent("par").path,
                frontendFlags: ["codegen-parallel", "jobs=4"],
                timer: timer
            )
            // The parallel path must actually have run — otherwise the test is vacuous.
            let phase = try #require(timer.phaseRecords.first)
            func namesIn(_ records: [PhaseTimer.PhaseRecord]) -> [String] {
                records.flatMap { [$0.name] + namesIn($0.subRecords) }
            }
            #expect(namesIn(phase.subRecords).contains("IR/partition merge"))

            let serialIR = try emitLLVMIR(
                inputPath: path,
                outputPath: directory.appendingPathComponent("ser").path,
                frontendFlags: []
            )
            #expect(!defineRows(serialIR).isEmpty)
            #expect(defineRows(parallelIR) == defineRows(serialIR))
            #expect(globalContentRows(parallelIR) == globalContentRows(serialIR))
            #expect(calledSymbols(parallelIR) == calledSymbols(serialIR))
        }
    }

    @Test
    func partitionedEmissionIsDeterministic() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let first = try emitLLVMIR(
                inputPath: path,
                outputPath: directory.appendingPathComponent("a").path,
                frontendFlags: ["codegen-parallel", "jobs=4"]
            )
            let second = try emitLLVMIR(
                inputPath: path,
                outputPath: directory.appendingPathComponent("b").path,
                frontendFlags: ["codegen-parallel", "jobs=4"]
            )
            #expect(first == second)
        }
    }

    @Test
    func partitionedEmissionLinksAndRuns() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "ParRun", inputs: [path], outputPath: outputPath,
                    emit: .executable, target: TargetTriple.hostDefault(),
                    frontendFlags: ["codegen-parallel", "jobs=4"], includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            timer.beginPhase("Codegen")
            try CodegenPhase().run(ctx)
            timer.endPhase()
            try LinkPhase().run(ctx)
            func namesIn(_ records: [PhaseTimer.PhaseRecord]) -> [String] {
                records.flatMap { [$0.name] + namesIn($0.subRecords) }
            }
            let phase = try #require(timer.phaseRecords.first)
            #expect(namesIn(phase.subRecords).contains("IR/partition merge"))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0)
        }
    }
}
#endif
