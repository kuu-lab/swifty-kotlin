@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct JavaLangIllegalArgumentExceptionTests {
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
    func javaLangImportConstructsAndCatchesKotlinIllegalArgumentException(
        fromSource: Bool,
        optimization: Int
    ) throws {
        try compileAndRun(sources: ["""
        import java.lang.IllegalArgumentException
        import java.lang.IllegalArgumentException as JavaIllegalArgumentException

        fun main() {
            val cause = Throwable("cause")
            val noArgument = IllegalArgumentException()
            check(noArgument.message == null)

            val messageOnly = IllegalArgumentException("message")
            check(messageOnly.message == "message")

            val causeOnly = JavaIllegalArgumentException(cause)
            check(causeOnly.cause === cause)
            check(causeOnly.message == cause.toString())

            val messageAndCause = JavaIllegalArgumentException("message and cause", cause)
            val kotlinType: kotlin.IllegalArgumentException = messageAndCause
            val importedType: IllegalArgumentException = kotlinType
            val aliasedType: JavaIllegalArgumentException = importedType
            check(aliasedType.message == "message and cause")
            check(aliasedType.cause === cause)
            check(aliasedType is kotlin.IllegalArgumentException)
            check(aliasedType.toString() == "java.lang.IllegalArgumentException: message and cause")

            try { require(false) { "bad argument" } }
            catch (e: IllegalArgumentException) { println(e.message) }
        }
        """],
        moduleName: "JavaLangIllegalArgumentException",
        fromSource: fromSource,
        optimization: optimization,
        expectedStdout: "bad argument\n")
    }

    @Test(arguments: [0, 2])
    func javaLangObjectTypeNameUsesKotlinAnyFromArtifact(optimization: Int) throws {
        try assertJavaLangObjectTypeNameUsesKotlinAny(fromSource: false, optimization: optimization)
    }

    @Test
    func javaLangObjectTypeNameUsesKotlinAnyFromSource() throws {
        try assertJavaLangObjectTypeNameUsesKotlinAny(fromSource: true, optimization: 0)
    }

    @Test
    func javaLangObjectTypeNameUsesKotlinAnyFromSourceO2() throws {
        try assertJavaLangObjectTypeNameUsesKotlinAny(fromSource: true, optimization: 2)
    }

    private func assertJavaLangObjectTypeNameUsesKotlinAny(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(sources: ["""
        class Monitor

        fun box(): String {
            val obj = Monitor() as java.lang.Object
            return "OK"
        }

        fun anyControl(): String {
            val obj = Monitor() as Any
            return "OK"
        }

        fun main() {
            print(box())
            print("\\n")
            print(anyControl())
            print("\\n")
        }
        """],
        moduleName: "JavaLangObjectTypeMapping",
        fromSource: fromSource,
        optimization: optimization,
        expectedStdout: "OK\nOK\n")
    }

    /// Uses Matrix.kt from https://github.com/DmitryTsyvtsyn/Kotlin-Algorithms-and-Design-Patterns/blob/1f89f062a056e24cc289ffdd0c6e23cadf8df887/src/main/kotlin/structures/Matrix.kt.
    @Test
    func pinnedMatrixConsumerKeepsItsOutput() throws {
        let matrixPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/KUU-1856/Matrix.kt")
        let matrixSource = try String(contentsOf: matrixPath, encoding: .utf8)
        let mainSource = """
        import structures.*

        fun main() {
            val a = matrix { row(1, 2); row(3, 4) }
            val b = matrix { row(5, 6); row(7, 8) }
            println(a + b)
            println(a * b)
        }
        """
        try compileAndRun(
            sources: [matrixSource, mainSource],
            moduleName: "KUU1856MatrixConsumer",
            fromSource: false,
            optimization: 0,
            expectedStdout: "\n6, 8\n10, 12\n\n\n19, 22\n43, 50\n\n"
        )
    }
}
