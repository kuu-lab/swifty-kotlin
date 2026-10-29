@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2020: imported format extensions must survive the synthetic-stub filter.
    @Test(arguments: [false, true])
    func testStringFormatLocaleOverloadsResolve(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        import java.util.Locale

        fun String.myfmt(l: Locale?, vararg a: Any?): String = this
        fun String.myfmt(vararg a: Any?): String = this

        fun main() {
            println("%s".format(Locale("en")))
            println("%s".format(Locale("en"), "x"))
            val l: Locale? = null
            println("%s".format(l, "x"))
            println("%s".format(null, "x"))
            println("%s".format("a"))
            println("%s".format("a", "b"))
            println(format("%s", Locale("en"), "x"))
            println(String.format(Locale("en"), "%s", "x"))
            println('a'.uppercase(Locale("en")))
            val x: Any = Locale("en")
            println("%s".myfmt(Locale("en")))
            println("%s".myfmt(Locale("en"), "x"))
            println("%s".myfmt(l, "x"))
            println("%s".myfmt("a", "b"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            try assertNoDiagnosticErrors(ctx)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func testStringFormatLocaleExtensionOutput(useArtifact: Bool, optimize: Bool) throws {
        let optLevel: OptimizationLevel = optimize ? .O2 : .O0
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource("string_format_locale_extension.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringFormatLocaleExtension",
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
            literal
            x
            nullable
            a|b
            null
            a
            a|b
            companion
            A
            true

            """)
        }
    }
}
