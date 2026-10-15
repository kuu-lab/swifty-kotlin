@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2239: resolve the SimpleDateFormat constructor and Date-returning
    /// parse call through source injection and a fresh shared stdlib artifact.
    @Test
    func testSimpleDateFormatSurfaceThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifact = try Self.buildStdlibArtifact()
        let forgeSurface = """
        import java.text.SimpleDateFormat
        import java.util.Date

        fun toDate(style: String = "EEE, dd MMM yyyy HH:mm:ss zzz"): (String) -> Date = {
            val formatter = SimpleDateFormat(style)
            formatter.parse(it)
        }

        fun formatter(style: String): SimpleDateFormat = SimpleDateFormat(style)
        fun parse(style: String, input: String): Date = SimpleDateFormat(style).parse(input)
        fun main() {
            parse("yyyy-MM-dd", "2020-01-02")
            toDate()("2020-01-02")
        }
        """
        let localControl = """
        class LocalDate(val input: String)
        class SimpleDateFormat(val pattern: String) {
            fun parse(input: String): LocalDate = LocalDate(input)
        }
        fun formatter(style: String): SimpleDateFormat = SimpleDateFormat(style)
        fun parse(style: String, input: String): LocalDate = SimpleDateFormat(style).parse(input)
        fun main() { parse("yyyy-MM-dd", "2020-01-02") }
        """

        for level in [OptimizationLevel.O0, .O2] {
            try withTemporaryFile(contents: forgeSurface) { input in
                let output = input + ".source"
                defer { try? FileManager.default.removeItem(atPath: output + ".kir") }
                let context = try runCodegenPipeline(
                    inputPath: input,
                    moduleName: "SimpleDateFormatSourceSurface",
                    emit: .kirDump,
                    outputPath: output,
                    optLevel: level,
                    allowDefaultStdlibLibrary: false
                )
                try assertNoDiagnosticErrors(context)
            }

            try withTemporaryFile(contents: forgeSurface) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: input,
                    moduleName: "SimpleDateFormatArtifactSurface",
                    outputPath: output,
                    optLevel: level,
                    allowDefaultStdlibLibrary: true,
                    stdlibLibraryPath: artifact
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                #expect(FileManager.default.fileExists(atPath: output))
            }
        }

        try withTemporaryFile(contents: localControl) { input in
            let output = input + ".local"
            defer { try? FileManager.default.removeItem(atPath: output + ".kir") }
            let context = try runCodegenPipeline(
                inputPath: input,
                moduleName: "SimpleDateFormatLocalControl",
                emit: .kirDump,
                outputPath: output,
                allowDefaultStdlibLibrary: false
            )
            try assertNoDiagnosticErrors(context)
        }
    }
}
