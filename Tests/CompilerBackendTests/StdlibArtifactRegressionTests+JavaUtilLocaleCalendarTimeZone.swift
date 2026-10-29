@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3066: Java locale and calendar APIs must work through a fresh bundled stdlib artifact.
    @Test(arguments: [false, true])
    func testLocaleCalendarAndTimeZoneSurface(optimize: Bool) throws {
        let optLevel: OptimizationLevel = optimize ? .O2 : .O0
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_util_locale_calendar_timezone.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "JavaUtilLocaleCalendarTimeZone",
                outputPath: outputBase,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            en_US
            ja_JP
            en
            ja_JP
            ja-JP
            en
            US
            English (United States)
            1,234.50
            true
            UTC
            0
            1970
            0
            1
            5
            UTC
            86400000

            """)
        }
    }
}
