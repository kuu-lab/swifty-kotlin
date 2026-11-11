@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibTryCatchFinallyExecutionTests {
    @Test(arguments: [0, 2])
    func executesSerializedTryCatchFinally(optimization: Int) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21")
        let producer = fixtures.appendingPathComponent("TryCatchFinally.kt").path
        let consumer = fixtures.appendingPathComponent("TryCatchFinallyConsumer.kt").path
        let library = fixtures.appendingPathComponent("try-catch-finally.klib").path
        let fm = FileManager.default
        try #require(fm.fileExists(atPath: library))
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let expected = """
        finally
        10
        Failed requirement.
        finally
        30
        number
        finally
        20
        finally
        outer finally
        unmatched
        40
        number
        finally
        number
        finally
        Check failed.
        1
        50
        1
        0
        1
        2
        2

        """

        for imported in [false, true] {
            let mode = imported ? "KLIB" : "source"
            let output = directory.appendingPathComponent(mode).path
            let result = makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "KlibTryCatchFinally",
                inputs: imported ? [consumer] : [producer, consumer],
                outputPath: output,
                emit: .executable,
                searchPaths: imported ? [library] : [],
                target: defaultTargetTriple(),
                optLevel: optimization == 0 ? .O0 : .O2
            ))
            try assertCompilationSucceeded(result, context: "\(mode) try/catch/finally at O\(optimization)")
            let importDiagnostics = result.diagnostics.filter {
                ["KSWIFTK-LIB-0027", "KSWIFTK-LIB-0028", "KSWIFTK-LIB-0029"].contains($0.code)
            }
            #expect(importDiagnostics.isEmpty, "\(importDiagnostics.map(\.message))")
            let run = try CommandRunner.run(executable: output, arguments: [])
            #expect(run.exitCode == 0, "\(mode) O\(optimization): \(run.stderr)")
            #expect(run.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(mode) O\(optimization)")
        }
    }
}
