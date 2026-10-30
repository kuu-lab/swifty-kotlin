@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct JavaLangIllegalStateExceptionTests {
    private func compileAndRun(
        sources: [String],
        moduleName: String,
        fromSource: Bool,
        optimization: Int,
        expectedStdout: String
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFiles(contents: sources) { inputs in
            let output = directory.appendingPathComponent(moduleName).path
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: inputs,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
                allowDefaultStdlibLibrary: !fromSource
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "\(moduleName) compilation"
            )

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expectedStdout)
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func javaLangImportConstructsAndAliasesKotlinIllegalStateException(
        fromSource: Bool,
        optimization: Int
    ) throws {
        try compileAndRun(sources: ["""
        import java.lang.IllegalStateException
        import java.lang.IllegalStateException as JavaIllegalStateException

        fun makeDirectJavaException(): IllegalStateException = IllegalStateException("direct")

        fun makeAliasedJavaException(cause: Throwable): JavaIllegalStateException =
            JavaIllegalStateException("aliased", cause)
        """, """
        import kotlin.IllegalStateException

        fun makeExplicitKotlinException(): IllegalStateException = IllegalStateException("explicit Kotlin")
        """, """
        fun makeDefaultKotlinException(): IllegalStateException = IllegalStateException("default Kotlin")
        """, """
        fun main() {
            val direct = makeDirectJavaException()
            val cause = Throwable("cause")
            val aliased: java.lang.IllegalStateException = makeAliasedJavaException(cause)
            val kotlinType: kotlin.IllegalStateException = aliased
            check(direct.message == "direct")
            check(aliased.message == "aliased")
            check(aliased.cause === cause)
            check(kotlinType is kotlin.IllegalStateException)
            check(makeExplicitKotlinException().message == "explicit Kotlin")
            check(makeDefaultKotlinException().message == "default Kotlin")
            try { error("state failure") }
            catch (e: java.lang.IllegalStateException) { println(e.message) }
        }
        """],
        moduleName: "JavaLangIllegalStateException",
        fromSource: fromSource,
        optimization: optimization,
        expectedStdout: "state failure\n")
    }
}
