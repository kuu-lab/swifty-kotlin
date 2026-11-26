#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension ParallelCodegenEmissionTests {
    private static let boundedPartitionSource = """
        object Registry { val base = 4 }
        open class Shape(val side: Int) { open fun area(): Int = side * side }
        class Rect(side: Int, val other: Int) : Shape(side) { override fun area(): Int = side * other }
        fun scale(a: Int, b: Int): Int = a * b
        fun offset(): (Int) -> Int = { it + 7 }
        fun tri(n: Int): Int = if (n <= 0) 0 else n + tri(n - 1)
        fun pick(x: Int): Int = when (x) { 0 -> 3; 1 -> 5; else -> 9 }
        var total = 0
        fun main() {
            val shape: Shape = Rect(2, 3)
            total = scale(shape.area(), offset()(pick(1))) + tri(4) + Registry.base
        }
        """

    private func compileBoundedPartitionExecutable(
        _ path: String, outputPath: String, frontendFlags: [String], optLevel: OptimizationLevel = .O0
    ) throws -> CompilationContext {
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "BoundedParRun", inputs: [path], outputPath: outputPath,
                emit: .executable, target: TargetTriple.hostDefault(), optLevel: optLevel,
                frontendFlags: frontendFlags, includeStdlib: false
            ),
            sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        try LinkPhase().run(ctx)
        return ctx
    }

    @Test
    func objectPartitionPlanSplitsPastWorkerCountByInstructionBudget() {
        let plan = NativeEmitter.planObjectPartitions(
            weights: [2, 2, 2, 2, 2, 2, 2, 2], workerCount: 2, maxWeightPerPartition: 4
        )
        #expect(plan.count == 4)
        #expect(plan.flatMap { $0 }.sorted() == Array(0 ..< 8))
        #expect(plan.allSatisfy { $0 == $0.sorted() })
    }

    @Test
    func objectPartitionPlanKeepsOnePartitionPerWorkerForSmallPrograms() {
        let plan = NativeEmitter.planObjectPartitions(
            weights: [3, 1, 2, 5], workerCount: 2, maxWeightPerPartition: CompilerOptions.defaultCodegenPartitionInstructions
        )
        #expect(plan.count == 2)
        #expect(plan.flatMap { $0 }.sorted() == [0, 1, 2, 3])
        #expect(NativeEmitter.planObjectPartitions(weights: [7, 7], workerCount: 8, maxWeightPerPartition: 1).count == 2)
        #expect(NativeEmitter.planObjectPartitions(weights: [], workerCount: 3, maxWeightPerPartition: 1).isEmpty)
    }

    @Test
    func objectPartitionPlanSpreadsHeavyFunctionsAndClaimsHeaviestFirst() {
        let weights = [100, 1, 1, 90, 1, 1, 80, 1, 1]
        let plan = NativeEmitter.planObjectPartitions(
            weights: weights, workerCount: 3, maxWeightPerPartition: 1_000_000
        )
        #expect(plan.count == 3)
        let heavy: Set = [0, 3, 6]
        #expect(plan.map { Set($0).intersection(heavy).count } == [1, 1, 1])
        let loads = plan.map { $0.reduce(0) { $0 + weights[$1] } }
        #expect(loads == loads.sorted(by: >))
    }

    @Test
    func executableInstructionBudgetSplitsObjectsBeyondWorkersAndRuns() throws {
        try withTemporaryFile(contents: Self.boundedPartitionSource) { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let split = try compileBoundedPartitionExecutable(
                path, outputPath: directory.appendingPathComponent("split").path,
                frontendFlags: ["codegen-parallel", "jobs=2", "codegen-partition-instructions=1"]
            )
            #expect(split.generatedObjectPaths.count > 3)
            for objectPath in split.generatedObjectPaths {
                let size = try FileManager.default.attributesOfItem(atPath: objectPath)[.size] as? NSNumber
                #expect((size?.intValue ?? 0) > 0, "\(objectPath)")
            }
            let splitRun = try CommandRunner.run(executable: split.options.outputPath, arguments: [])
            #expect(splitRun.exitCode == 0, "\(splitRun.stderr)")

            let perWorker = try compileBoundedPartitionExecutable(
                path, outputPath: directory.appendingPathComponent("per-worker").path,
                frontendFlags: ["codegen-parallel", "jobs=2"]
            )
            #expect(perWorker.generatedObjectPaths.count == 3)
            let perWorkerRun = try CommandRunner.run(executable: perWorker.options.outputPath, arguments: [])
            #expect(perWorkerRun.exitCode == 0, "\(perWorkerRun.stderr)")
        }
    }

    @Test
    func startupReflectionInitializerNamesAreRecognized() {
        #expect(NativeEmitter.isStartupReflectionInitializer("__ctor_reflect_init_42"))
        #expect(!NativeEmitter.isStartupReflectionInitializer("__object_init_42"))
        #expect(!NativeEmitter.isStartupReflectionInitializer("main"))
    }

    @Test
    func optimizedBuildsEmitStartupReflectionInitializersIntoTheirOwnObject() throws {
        try withTemporaryFile(contents: Self.boundedPartitionSource) { path in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let optimized = try compileBoundedPartitionExecutable(
                path, outputPath: directory.appendingPathComponent("o2").path,
                frontendFlags: ["codegen-parallel", "jobs=2"], optLevel: .O2
            )
            #expect(optimized.generatedObjectPaths.count == 4)
            let optimizedRun = try CommandRunner.run(executable: optimized.options.outputPath, arguments: [])
            #expect(optimizedRun.exitCode == 0, "\(optimizedRun.stderr)")

            let unoptimized = try compileBoundedPartitionExecutable(
                path, outputPath: directory.appendingPathComponent("o0").path,
                frontendFlags: ["codegen-parallel", "jobs=2"], optLevel: .O0
            )
            #expect(unoptimized.generatedObjectPaths.count == 3)
        }
    }

    @Test
    func libraryInstructionBudgetSplitsObjectsBeyondWorkersAndLinks() throws {
        try withTemporaryFile(contents: Self.boundedPartitionSource.replacingOccurrences(of: "fun main() {", with: "fun libraryEntry() {")) { libSourcePath in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let libBase = directory.appendingPathComponent("BoundedParLib").path
            let libCtx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "BoundedParLib", inputs: [libSourcePath], outputPath: libBase,
                    emit: .library, target: TargetTriple.hostDefault(),
                    frontendFlags: ["codegen-parallel", "jobs=2", "codegen-partition-instructions=1"],
                    includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let kklibDir = libBase + ".kklib"
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: kklibDir).appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let objects = try #require(manifest["objects"] as? [String])
            #expect(objects.count > 3)
            #expect(Set(objects).count == objects.count)
            for relPath in objects {
                #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: kklibDir).appendingPathComponent(relPath).path))
            }

            let mainPath = directory.appendingPathComponent("main.kt").path
            let exePath = directory.appendingPathComponent("main_out").path
            try """
            fun main() {
                libraryEntry()
                total = total + scale(Rect(1, 2).area(), tri(2))
            }
            """.write(toFile: mainPath, atomically: true, encoding: .utf8)
            let mainCtx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "UseBoundedParLib", inputs: [mainPath], outputPath: exePath,
                    emit: .executable, searchPaths: [kklibDir], target: TargetTriple.hostDefault(),
                    includeStdlib: false
                ),
                sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(mainCtx)
            try LoweringPhase().run(mainCtx)
            try CodegenPhase().run(mainCtx)
            try LinkPhase().run(mainCtx)
            let result = try CommandRunner.run(executable: exePath, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
        }
    }
}
#endif
