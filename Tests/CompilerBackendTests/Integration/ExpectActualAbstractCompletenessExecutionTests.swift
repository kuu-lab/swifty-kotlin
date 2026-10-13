#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualAbstractCompletenessExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func expectMayDeferInheritedImplementationToActual(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFiles(contents: [
            """
            abstract class Token { abstract fun match(): Int }
            expect class RegexToken : Token { constructor() }
            fun main() { println(RegexToken().match()) }
            """,
            """
            actual class RegexToken actual constructor() : Token() {
                override fun match() = 3
            }
            """,
        ]) { inputs in
            let output = directory.appendingPathComponent("expect-actual").path
            let options = CompilerOptions(
                moduleName: "ExpectActualAbstractCompleteness",
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
                context: "expect/actual abstract completeness"
            )

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
            #expect(result.stdout == "3\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test(arguments: [0, 2])
    func separatelyCompiledConsumerRetainsTheExpectedBaseType(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try withTemporaryFile(contents: """
            package kuu1916
            abstract class Token { abstract fun match(): Int }
            expect class RegexToken : Token { constructor() }
            """) { libraryInput in
            let libraryOutput = directory.appendingPathComponent("ExpectActualLibrary").path
            let libraryOptions = CompilerOptions(
                moduleName: "ExpectActualLibrary",
                inputs: [libraryInput],
                outputPath: libraryOutput,
                emit: .library,
                target: defaultTargetTriple(),
                optLevel: level,
                stdlibLibraryPath: stdlib
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: libraryOptions),
                context: "expect/actual library"
            )

            try withTemporaryFiles(contents: [
                """
                package kuu1916
                actual class RegexToken actual constructor() : Token() {
                    override fun match() = 3
                }
                """,
                """
                import kuu1916.RegexToken
                import kuu1916.Token

                fun main() {
                    val token: Token = RegexToken()
                    println(token.match())
                }
                """,
            ]) { consumerInputs in
                let consumerOutput = directory.appendingPathComponent("ExpectActualConsumer").path
                let consumerOptions = CompilerOptions(
                    moduleName: "ExpectActualConsumer",
                    inputs: consumerInputs,
                    outputPath: consumerOutput,
                    emit: .executable,
                    searchPaths: [libraryOutput + ".kklib"],
                    target: defaultTargetTriple(),
                    optLevel: level,
                    stdlibLibraryPath: stdlib
                )
                try assertCompilationSucceeded(
                    makeTestDriver().runForTesting(options: consumerOptions),
                    context: "expect/actual consumer"
                )

                let result = try CommandRunner.run(executable: consumerOutput, arguments: [])
                #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
                #expect(result.stdout == "3\n")
                #expect(result.stderr.isEmpty)
            }
        }
    }
}
#endif
