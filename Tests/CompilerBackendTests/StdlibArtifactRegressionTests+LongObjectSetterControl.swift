@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2683 (BUG-266): assignments to `Long` properties of an imported
    /// `object` must reach their accessors. `minBytes`/`maxBytes` write
    /// through custom setters onto private backing vars, `plainLong` keeps
    /// the flat-global backing-field path, `silentA`/`silentB` prove a
    /// misbound `set` call cannot drop a write silently, and the `+=` on
    /// `minBytes` exercises the getter/setter round trip that used to read
    /// and write a dead flat-global slot.
    ///
    /// false compiles producer and consumer together from source; true emits
    /// a real user .kklib first and compiles only the consumer against it.
    @Test(arguments: [false, true])
    func testLongObjectSetterControlRoundTrip(useProducerLibrary: Bool) throws {
        let stdlibArtifactPath = try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = repoRoot.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/LongObjectSetterControl", isDirectory: true
        )
        let producerPath = fixtures.appendingPathComponent("producer.kt").path
        let consumerPath = fixtures.appendingPathComponent("consumer.kt").path
        let expected = try String(
            contentsOf: fixtures.appendingPathComponent("expected.stdout"),
            encoding: .utf8
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var searchPaths: [String] = []
        var inputs = [producerPath, consumerPath]
        if useProducerLibrary {
            let libraryBase = directory.appendingPathComponent("longobjsetter").path
            let libraryCtx = makeCompilationContext(
                inputs: [producerPath],
                moduleName: "longobjsetter",
                emit: .library,
                outputPath: libraryBase,
                includeStdlib: false,
                stdlibLibraryPath: stdlibArtifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)
            #expect(!libraryCtx.diagnostics.hasError, "Producer diagnostics: \(libraryCtx.diagnostics.diagnostics)")
            let libraryPath = libraryBase + ".kklib"
            #expect(
                FileManager.default.fileExists(atPath: libraryPath + "/manifest.json"),
                "Producer .kklib should be emitted at \(libraryPath)"
            )
            searchPaths = [libraryPath]
            inputs = [consumerPath]
        }

        let executable = directory.appendingPathComponent("consumer").path
        let ctx = makeCompilationContext(
            inputs: inputs,
            moduleName: "LongObjectSetterConsumer",
            emit: .executable,
            outputPath: executable,
            searchPaths: searchPaths,
            includeStdlib: false,
            stdlibLibraryPath: stdlibArtifactPath,
            allowDefaultStdlibLibrary: false
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        try LinkPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError, "Consumer diagnostics: \(ctx.diagnostics.diagnostics)")

        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(
            result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
            "HeapBox output diverged (useProducerLibrary=\(useProducerLibrary))"
        )
    }
}
