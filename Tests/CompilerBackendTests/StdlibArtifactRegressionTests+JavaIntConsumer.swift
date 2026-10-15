@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testJavaIntConsumerFacadeThroughFreshStdlibArtifactAtO0AndO2() throws {
        // This regression is compile-only; callback runtime behavior is not exercised here.
        let artifact = try Self.buildStdlibArtifact()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sources: [(String, String)] = [
            ("JSONValue.kt", """
            package io.kjson
            import java.util.function.IntConsumer

            fun IntConsumer.accept(cs: CharSequence) {
                cs.forEach { accept(it.code) }
            }

            fun intConsumerSamControl(): IntConsumer = IntConsumer { _ -> }

            interface Value {
                fun toJSON(): String
                fun outputTo(out: IntConsumer) { out.accept(toJSON()) }
            }
            """),
            ("LocalSamControl.kt", """
            private fun interface LocalConsumer {
                fun accept(value: Int)
            }

            private fun localSamControl(): LocalConsumer = LocalConsumer { _ -> }
            """),
            ("FunctionTypeControl.kt", """
            private fun functionTypeControl(consumer: (Int) -> Unit) {
                consumer(1)
            }
            """),
        ]
        let inputPaths = try sources.map { name, source in
            let path = directory.appendingPathComponent(name)
            try source.write(to: path, atomically: true, encoding: .utf8)
            return path.path
        }

        for level in [OptimizationLevel.O0, .O2] {
            let outputPath = directory.appendingPathComponent("JavaIntConsumer-\(level)").path
            let options = CompilerOptions(
                moduleName: "JavaIntConsumerConsumer",
                inputs: inputPaths,
                outputPath: outputPath,
                emit: .library,
                target: defaultTargetTriple(),
                optLevel: level,
                includeStdlib: false,
                stdlibLibraryPath: artifact,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            #expect(FileManager.default.fileExists(atPath: outputPath + ".kklib"))
        }
    }
}
