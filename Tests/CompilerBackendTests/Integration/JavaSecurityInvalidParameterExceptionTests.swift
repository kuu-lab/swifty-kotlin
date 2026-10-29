@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct JavaSecurityInvalidParameterExceptionTests {
    private func compile(
        sources: [String],
        moduleName: String,
        optimization: Int,
        emit: EmitMode,
        inspectOutput: (String) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        return try withTemporaryFiles(contents: sources) { inputs in
            let output = directory.appendingPathComponent(moduleName).path
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: inputs,
                outputPath: output,
                emit: emit,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: try testStdlibArtifactPath(),
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "\(moduleName) compilation"
            )
            try inspectOutput(output)
        }
    }

    @Test(arguments: [0, 2])
    func pinnedFactorialAndCompileContractsUseStdlibArtifact(optimization: Int) throws {
        let fixtureDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/KUU-2221")
        let factorial = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("Factorial.kt"),
            encoding: .utf8
        )
        let minimalReproducer = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("MinimalReproducer.kt"),
            encoding: .utf8
        )
        let contracts = """
        package regression

        fun qualified(n: Long): Long {
            if (n < 0L) throw java.security.InvalidParameterException("qualified")
            return n
        }
        """
        let importsAndBoundaries = """
        package regression

        import java.security.InvalidParameterException
        import java.lang.IllegalArgumentException

        fun explicitlyImported(n: Long): Long {
            if (n < 0L) throw InvalidParameterException("explicit")
            return n
        }

        fun asParent(error: InvalidParameterException): IllegalArgumentException = error

        fun catchInvalidParameter(action: () -> Unit): String = try {
            action()
            ""
        } catch (error: InvalidParameterException) {
            val parent: IllegalArgumentException = error
            parent.message ?: ""
        }

        fun catchIllegalArgument(action: () -> Unit): String = try {
            action()
            ""
        } catch (error: IllegalArgumentException) {
            error.message ?: ""
        }

        fun allConstructors(cause: Throwable): InvalidParameterException {
            InvalidParameterException()
            InvalidParameterException("message")
            InvalidParameterException("message and cause", cause)
            return InvalidParameterException(cause)
        }
        """

        try compile(
            sources: [factorial, minimalReproducer, contracts, importsAndBoundaries],
            moduleName: "KUU2221ArtifactCompileO\(optimization)",
            optimization: optimization,
            emit: .object
        ) { output in
            #expect(FileManager.default.fileExists(atPath: output + ".o"))
        }
    }

    @Test
    func nativeExceptionPreservesSpecificAndParentCatchBoundaries() throws {
        let source = """
        import java.security.InvalidParameterException
        import java.lang.IllegalArgumentException

        fun main() {
            val cause = RuntimeException("cause")
            val noArgument = InvalidParameterException()
            check(noArgument.message == null)

            val messageOnly = InvalidParameterException("message")
            check(messageOnly.message == "message")

            val messageAndCause = InvalidParameterException("message and cause", cause)
            check(messageAndCause.message == "message and cause")
            check(messageAndCause.cause === cause)

            val causeOnly = InvalidParameterException(cause)
            check(causeOnly.message == cause.toString())
            check(causeOnly.cause === cause)

            val invalid = InvalidParameterException("negative")
            check(invalid is InvalidParameterException)
            check(invalid is IllegalArgumentException)
            try { throw invalid }
            catch (error: InvalidParameterException) { println("specific:${error.message}") }
            try { throw invalid }
            catch (error: IllegalArgumentException) { println("parent:${error.message}") }

            val ordinary = IllegalArgumentException("ordinary")
            try { throw ordinary }
            catch (error: InvalidParameterException) { println("wrong") }
            catch (error: IllegalArgumentException) { println("parent-only") }
        }
        """
        try compile(
            sources: [source],
            moduleName: "KUU2221NativeCatchBoundaries",
            optimization: 0,
            emit: .executable
        ) { output in
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "specific:negative\nparent:negative\nparent-only\n"
            )
        }
    }
}
