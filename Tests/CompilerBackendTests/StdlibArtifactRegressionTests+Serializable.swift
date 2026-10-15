@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2389: `java.io.Serializable` must resolve from source and a fresh
    /// stdlib artifact as both an explicit import and a qualified supertype.
    @Test
    func testJavaSerializableDataClassAcrossStdlibSurfaces() throws {
        let source = try diffCaseSource("kt5002_java_io_serializable.kt", file: #filePath)
        let artifact = try Self.buildStdlibArtifact()

        for (surface, library) in [("source", nil), ("fresh artifact", artifact)] as [(String, String?)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }

                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "KUU2389Serializable",
                        outputPath: output,
                        optLevel: optimization,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: library
                    )
                    try assertNoDiagnosticErrors(context)

                    let sema = try #require(context.sema)
                    let serializable = try #require(sema.symbols.lookup(fqName:
                        ["java", "io", "Serializable"].map(context.interner.intern)))
                    #expect(sema.symbols.symbol(serializable)?.kind == .interface)
                    if library == nil {
                        let isSourceBacked = sema.symbols.isSourceBackedSymbol(serializable)
                        #expect(isSourceBacked)
                    }

                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(surface), \(optimization): \(result.stderr)")
                    #expect(result.stderr.isEmpty)
                    #expect(result.stdout == "OK", "\(surface), \(optimization): \(result.stdout)")
                }
            }
        }
    }
}
