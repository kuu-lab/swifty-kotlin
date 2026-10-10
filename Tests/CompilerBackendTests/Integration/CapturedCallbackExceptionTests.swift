import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct CapturedCallbackExceptionTests {
    @Test(arguments: [false, true], [0, 2])
    func capturedCallbacksPropagateExceptionsLikeJVM(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = repository.appendingPathComponent("Scripts/reference_cases/captured_callback_exceptions.kt")
        let input = directory.appendingPathComponent("callbacks.kt").path
        try String(contentsOf: fixture, encoding: .utf8).write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("callbacks").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "CapturedCallbackExceptions", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        let expected = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/reference_cases/captured_callback_exceptions.expected"), encoding: .utf8)
        #expect(result.stdout == expected)
    }
}
