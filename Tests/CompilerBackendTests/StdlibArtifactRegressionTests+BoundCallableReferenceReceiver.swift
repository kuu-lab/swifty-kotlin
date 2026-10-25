@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-3469: a bound reference to Map.size must keep using the runtime
    /// bridge instead of dispatching through a nonexistent object vtable.
    @Test
    func testBoundMapSizePropertyReferenceGetsValue() throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = try #require(
            CompilerOptions.defaultStdlibLibraryPath,
            "Expected the content-addressed fresh stdlib artifact"
        )
        let source = """
        fun main() {
            val map = mapOf(1 to "a")
            println(map.size)
            val reference = map::size
            println(reference.get())
        }
        """

        let output = try runBoundCallableReferenceReceiver(
            source,
            moduleName: "KUU3469BoundMapSize",
            stdlibLibraryPath: artifactPath,
            optLevel: .O0
        )
        #expect(
            output == "1\n1\n",
            "Unexpected output: \(String(reflecting: output))"
        )
    }

    /// KUU-2304: a bound callable reference used as a generic extension
    /// receiver must retain its function type when the extension lambda is
    /// checked.
    @Test
    func testBoundCallableReferenceReceiverAcrossStdlibSurfaces() throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = try #require(
            CompilerOptions.defaultStdlibLibraryPath,
            "Expected the content-addressed fresh stdlib artifact"
        )
        let source = """
        class Generic<P : Any>(val p: P)

        class Host {
            fun t() {}
            val v = "OK"
        }

        fun <T, R> apply(value: T, block: (T) -> R): R = block(value)

        fun box(): String {
            Generic(Host()).p::class
            (Generic(Host()).p::t).let { it() }
            return (Generic(Host()).p::v).let { it() }
        }

        fun main() {
            // The typed, ordinary-receiver, and generic-HOF cases are controls
            // for the untyped reference passed to the generic extension receiver.
            ((Host()::t) as () -> Unit).let { it() }
            Host().let { it.t() }
            apply(Host()::t) { it() }
            val local: () -> Unit = Host()::t
            local()
            println(box())
        }
        """

        let surfaces: [(name: String, libraryPath: String?)] = [
            ("source", nil),
            ("fresh .kklib", artifactPath),
        ]

        for (surface, libraryPath) in surfaces {
            for optimizationLevel in [OptimizationLevel.O0, .O2] {
                let output = try runBoundCallableReferenceReceiver(
                    source,
                    moduleName: "KUU2304BoundCallableReceiver_\(surface)_\(optimizationLevel.rawValue)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optimizationLevel
                )
                #expect(
                    output == "OK\n",
                    "Unexpected output using \(surface) at \(optimizationLevel): \(String(reflecting: output))"
                )
            }
        }
    }
}

private func runBoundCallableReferenceReceiver(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: outputBase) }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        try runToKIR(context)
        try assertNoDiagnosticErrors(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        try LinkPhase().run(context)

        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        guard result.exitCode == 0 else {
            throw TestCompilationFailure(
                description: "Execution failed with exit \(result.exitCode): \(result.stderr)"
            )
        }
        output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return output
}
