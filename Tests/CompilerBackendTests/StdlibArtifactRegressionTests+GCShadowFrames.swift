@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testRootedWeakReadThroughStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.clear
        class Payload(val value: Int)
        fun main() {
            val target = Payload(42)
            val weak = WeakReference(target)
            println(weak.value?.value ?: -1)
            java.lang.System.gc()
            println(weak.value === target)
            weak.clear()
            println(weak.value == null)
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            for level in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let context = try runCodegenPipeline(
                    inputPath: inputPath, moduleName: "GCRootedWeakRead", outputPath: outputPath,
                    optLevel: level, allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath, prepareTestStdlibCache: false
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 30)
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "42\ntrue\ntrue\n")
            }
        }
    }

    @Test
    func testGCThreadLocalGlobalAcrossLibrary() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let librarySource = directory.appendingPathComponent("ThreadLocal.kt")
        let libraryOutput = directory.appendingPathComponent("ThreadLocalLibrary").path
        try """
        @file:Suppress("DEPRECATION_ERROR")
        package fixture
        import kotlin.native.concurrent.ThreadLocal
        @ThreadLocal var value: Any? = null
        """.write(to: librarySource, atomically: true, encoding: .utf8)
        let libraryOptions = CompilerOptions(
            moduleName: "ThreadLocalLibrary", inputs: [librarySource.path], outputPath: libraryOutput,
            emit: .library, target: CompilerTestSupport.defaultTargetTriple(),
            stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
        )
        let library = CompilationContext(
            options: libraryOptions, sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(), interner: StringInterner()
        )
        try runToKIR(library)
        try LoweringPhase().run(library)
        try CodegenPhase().run(library)
        try assertNoDiagnosticErrors(library)
        let consumerSource = """
        @file:Suppress("DEPRECATION_ERROR")
        import fixture.value
        import kotlin.concurrent.thread
        fun main() {
            val worker = thread { value = Any(); println(value != null) }
            worker.join()
            java.lang.System.gc()
            println(value == null)
        }
        """
        try withTemporaryFile(contents: consumerSource) { inputPath in
            let outputPath = directory.appendingPathComponent("consumer").path
            let options = CompilerOptions(
                moduleName: "ThreadLocalConsumer", inputs: [inputPath], outputPath: outputPath,
                emit: .executable, searchPaths: [libraryOutput + ".kklib"],
                target: CompilerTestSupport.defaultTargetTriple(), stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            let context = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 30)
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\ntrue\n")
        }
    }

    @Test
    func testGCShadowFramesAcrossReturnsAndExceptions() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        private fun shadowDepth(): Long = 0L

        fun nested(): Long = shadowDepth()
        fun normalReturn(value: Boolean) {
            if (value) return
        }
        fun throwing() { throw IllegalStateException("test") }
        fun relay() { throwing() }

        fun main() {
            val baseline = shadowDepth()
            println(baseline > 0L)
            println(nested() == baseline + 1L)
            normalReturn(true)
            println(shadowDepth() == baseline)
            try { relay() } catch (_: IllegalStateException) {}
            println(shadowDepth() == baseline)
            println(nested() == baseline + 1L)
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            for level in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let options = CompilerOptions(
                    moduleName: "GCShadowFrames", inputs: [inputPath], outputPath: outputPath,
                    emit: .executable, target: CompilerTestSupport.defaultTargetTriple(), optLevel: level,
                    stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
                )
                let context = CompilationContext(
                    options: options, sourceManager: SourceManager(),
                    diagnostics: DiagnosticEngine(), interner: StringInterner()
                )
                try runToKIR(context)
                try assertNoDiagnosticErrors(context)
                let kir = try #require(context.kir)
                let sema = try #require(context.sema)
                let depth = kir.arena.appendTemporary(type: sema.types.longType)
                let callee = context.interner.intern("kk_gc_shadow_depth")
                var replaced = 0
                kir.arena.transformFunctions { original in
                    guard context.interner.resolve(original.name) == "shadowDepth" else { return original }
                    var function = original
                    function.replaceBody([
                        .call(callee: callee, arguments: [], result: depth, canThrow: false),
                        .returnValue(depth),
                    ], locations: [nil, nil])
                    replaced += 1
                    return function
                }
                #expect(replaced == 1)
                try LoweringPhase().run(context)
                try CodegenPhase().run(context)
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 30)
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\ntrue\ntrue\ntrue\ntrue\n")
            }
        }
    }

    @Test
    func testSameFrameWeakReferenceAndUnreferencedTimerThroughStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.ref.WeakReference
        import java.util.Timer
        import java.util.TimerTask

        class Foo(val value: Int)

        fun main() {
            var current: Foo? = Foo(42)
            val weak = WeakReference(current!!)
            System.gc()
            println("live=" + current!!.value)
            println("weakLive=" + weak.value?.value)
            current = null
            repeat(10) {
                System.gc()
                Thread.sleep(20)
            }
            println("cleared=" + (weak.value == null))

            var timer: Timer? = Timer()
            timer!!.schedule(object : TimerTask() {
                override fun run() { println("task finished") }
            }, 30L)
            Thread.sleep(150L)
            timer = null
            repeat(10) {
                System.gc()
                Thread.sleep(20L)
            }
            println("main finished")
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            for level in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let context = try runCodegenPipeline(
                    inputPath: inputPath, moduleName: "GCSameFrameWeakRefAndTimer", outputPath: outputPath,
                    optLevel: level, allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath, prepareTestStdlibCache: false
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 15)
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(
                    result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                        == "live=42\nweakLive=42\ncleared=true\ntask finished\nmain finished\n"
                )
            }
        }
    }
}
