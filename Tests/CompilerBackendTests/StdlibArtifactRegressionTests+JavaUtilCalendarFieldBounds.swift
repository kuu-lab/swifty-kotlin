@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-4288: `Calendar.getMinimum`/`getMaximum`/`getGreatestMinimum`/
    /// `getLeastMaximum`/`getActualMinimum`/`getActualMaximum` must resolve and
    /// produce JDK-compatible values through a fresh bundled stdlib artifact.
    @Test(arguments: [false, true])
    func testCalendarFieldBoundsSurface(optimize: Bool) throws {
        let optLevel: OptimizationLevel = optimize ? .O2 : .O0
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_util_calendar_field_bounds.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "JavaUtilCalendarFieldBounds",
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
            f=0 min=0 max=1 gmin=0 lmax=1
            f=1 min=1 max=292278994 gmin=1 lmax=292269054
            f=2 min=0 max=11 gmin=0 lmax=11
            f=3 min=1 max=53 gmin=1 lmax=50
            f=4 min=0 max=6 gmin=0 lmax=3
            f=5 min=1 max=31 gmin=1 lmax=28
            f=6 min=1 max=366 gmin=1 lmax=355
            f=7 min=1 max=7 gmin=1 lmax=7
            f=8 min=1 max=6 gmin=1 lmax=3
            f=9 min=0 max=1 gmin=0 lmax=1
            f=10 min=0 max=11 gmin=0 lmax=11
            f=11 min=0 max=23 gmin=0 lmax=23
            f=12 min=0 max=59 gmin=0 lmax=59
            f=13 min=0 max=59 gmin=0 lmax=59
            f=14 min=0 max=999 gmin=0 lmax=999
            f=15 min=-46800000 max=50400000 gmin=-46800000 lmax=50400000
            f=16 min=0 max=7200000 gmin=0 lmax=1200000
            1969-04-01 f=0 amin=0 amax=1
            1969-04-01 f=1 amin=1 amax=292278994
            1969-04-01 f=2 amin=0 amax=11
            1969-04-01 f=3 amin=1 amax=52
            1969-04-01 f=4 amin=0 amax=5
            1969-04-01 f=5 amin=1 amax=30
            1969-04-01 f=6 amin=1 amax=365
            1969-04-01 f=7 amin=1 amax=7
            1969-04-01 f=8 amin=1 amax=5
            1969-04-01 f=9 amin=0 amax=1
            1969-04-01 f=10 amin=0 amax=11
            1969-04-01 f=11 amin=0 amax=23
            1969-04-01 f=12 amin=0 amax=59
            1969-04-01 f=13 amin=0 amax=59
            1969-04-01 f=14 amin=0 amax=999
            1969-04-01 f=15 amin=-46800000 amax=50400000
            1969-04-01 f=16 amin=0 amax=7200000
            2024-02-15 f=0 amin=0 amax=1
            2024-02-15 f=1 amin=1 amax=292278994
            2024-02-15 f=2 amin=0 amax=11
            2024-02-15 f=3 amin=1 amax=52
            2024-02-15 f=4 amin=0 amax=5
            2024-02-15 f=5 amin=1 amax=29
            2024-02-15 f=6 amin=1 amax=366
            2024-02-15 f=7 amin=1 amax=7
            2024-02-15 f=8 amin=1 amax=5
            2024-02-15 f=9 amin=0 amax=1
            2024-02-15 f=10 amin=0 amax=11
            2024-02-15 f=11 amin=0 amax=23
            2024-02-15 f=12 amin=0 amax=59
            2024-02-15 f=13 amin=0 amax=59
            2024-02-15 f=14 amin=0 amax=999
            2024-02-15 f=15 amin=-46800000 amax=50400000
            2024-02-15 f=16 amin=0 amax=7200000
            2023-02-15 f=0 amin=0 amax=1
            2023-02-15 f=1 amin=1 amax=292278994
            2023-02-15 f=2 amin=0 amax=11
            2023-02-15 f=3 amin=1 amax=52
            2023-02-15 f=4 amin=0 amax=5
            2023-02-15 f=5 amin=1 amax=28
            2023-02-15 f=6 amin=1 amax=365
            2023-02-15 f=7 amin=1 amax=7
            2023-02-15 f=8 amin=1 amax=4
            2023-02-15 f=9 amin=0 amax=1
            2023-02-15 f=10 amin=0 amax=11
            2023-02-15 f=11 amin=0 amax=23
            2023-02-15 f=12 amin=0 amax=59
            2023-02-15 f=13 amin=0 amax=59
            2023-02-15 f=14 amin=0 amax=999
            2023-02-15 f=15 amin=-46800000 amax=50400000
            2023-02-15 f=16 amin=0 amax=7200000
            2022-01-15 f=0 amin=0 amax=1
            2022-01-15 f=1 amin=1 amax=292278994
            2022-01-15 f=2 amin=0 amax=11
            2022-01-15 f=3 amin=1 amax=53
            2022-01-15 f=4 amin=0 amax=6
            2022-01-15 f=5 amin=1 amax=31
            2022-01-15 f=6 amin=1 amax=365
            2022-01-15 f=7 amin=1 amax=7
            2022-01-15 f=8 amin=1 amax=5
            2022-01-15 f=9 amin=0 amax=1
            2022-01-15 f=10 amin=0 amax=11
            2022-01-15 f=11 amin=0 amax=23
            2022-01-15 f=12 amin=0 amax=59
            2022-01-15 f=13 amin=0 amax=59
            2022-01-15 f=14 amin=0 amax=999
            2022-01-15 f=15 amin=-46800000 amax=50400000
            2022-01-15 f=16 amin=0 amax=7200000
            2023-12-31 f=0 amin=0 amax=1
            2023-12-31 f=1 amin=1 amax=292278993
            2023-12-31 f=2 amin=0 amax=11
            2023-12-31 f=3 amin=1 amax=52
            2023-12-31 f=4 amin=0 amax=6
            2023-12-31 f=5 amin=1 amax=31
            2023-12-31 f=6 amin=1 amax=365
            2023-12-31 f=7 amin=1 amax=7
            2023-12-31 f=8 amin=1 amax=5
            2023-12-31 f=9 amin=0 amax=1
            2023-12-31 f=10 amin=0 amax=11
            2023-12-31 f=11 amin=0 amax=23
            2023-12-31 f=12 amin=0 amax=59
            2023-12-31 f=13 amin=0 amax=59
            2023-12-31 f=14 amin=0 amax=999
            2023-12-31 f=15 amin=-46800000 amax=50400000
            2023-12-31 f=16 amin=0 amax=7200000
            2024-12-31 f=0 amin=0 amax=1
            2024-12-31 f=1 amin=1 amax=292278993
            2024-12-31 f=2 amin=0 amax=11
            2024-12-31 f=3 amin=1 amax=52
            2024-12-31 f=4 amin=0 amax=5
            2024-12-31 f=5 amin=1 amax=31
            2024-12-31 f=6 amin=1 amax=366
            2024-12-31 f=7 amin=1 amax=7
            2024-12-31 f=8 amin=1 amax=5
            2024-12-31 f=9 amin=0 amax=1
            2024-12-31 f=10 amin=0 amax=11
            2024-12-31 f=11 amin=0 amax=23
            2024-12-31 f=12 amin=0 amax=59
            2024-12-31 f=13 amin=0 amax=59
            2024-12-31 f=14 amin=0 amax=999
            2024-12-31 f=15 amin=-46800000 amax=50400000
            2024-12-31 f=16 amin=0 amax=7200000
            dim=30 offs+dim=37

            """)
        }
    }
}
