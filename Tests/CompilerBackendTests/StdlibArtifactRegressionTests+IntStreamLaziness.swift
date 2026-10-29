@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3647: IntStream callbacks are deferred and terminals stop pulling once decided.
    @Test(arguments: [true, false], [0, 2])
    func testIntStreamLazinessThroughSourceAndFreshArtifact(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_intstream_lazy_short_circuit.kt", file: #filePath)
        let inputPath = directory.appendingPathComponent("main.kt").path
        try source.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let outputPath = directory.appendingPathComponent("intstream-laziness").path
        let options = CompilerOptions(
            moduleName: "KUU3647IntStreamLaziness",
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == """
        before=0
        first=65
        after=1
        ordered-before=0,0
        ordered=5
        ordered-after=3,2
        any=true,calls=2
        empty=0,calls=0
        exception-before=0
        exception=thrown
        exception-after=2
        boxed-before=0
        boxed-any=true
        boxed-after=1
        object-before=0
        object-any=true
        object-after=1
        parent-reuse=illegal
        derived-count=2
        terminal-reuse=illegal

        """)
    }
}
