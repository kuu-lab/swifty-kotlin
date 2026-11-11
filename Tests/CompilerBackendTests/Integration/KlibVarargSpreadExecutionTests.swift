@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibVarargSpreadExecutionTests {
    @Test(arguments: [0, 2])
    func executesLatestNativeKlibVarargSpreads(optimization: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/VarargSpread")
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let output = directory.appendingPathComponent("consumer").path
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "KlibVarargSpread",
            inputs: [fixture.appendingPathComponent("Consumer.kt").path],
            outputPath: output, emit: .executable,
            searchPaths: [fixture.appendingPathComponent("varargspread.klib").path],
            target: defaultTargetTriple(), optLevel: optimization == 0 ? .O0 : .O2,
            frontendFlags: ["no-incremental"],
            stdlibLibraryPath: try testStdlibArtifactPath()
        ))
        try assertCompilationSucceeded(result, context: "Kotlin/Native 2.4.21 KLIB vararg spread O\(optimization)")
        #expect(!result.diagnostics.contains { $0.code == "KSWIFTK-LIB-0029" })
        let run = try CommandRunner.run(executable: output, arguments: [], timeout: 30)
        #expect(run.exitCode == 0, "\(run.stderr)")
        // Checked against Kotlin/JVM 2.4.21 with the same producer and consumer sources.
        #expect(run.stdout == """
        10
        5
        12345
        [1, 20, 21, 3, 40, 5]
        true
        [2, 3]
        [99, 3]
        0
        [head, null, left, 7, right, !, null]
        true
        true

        """)
    }
}
