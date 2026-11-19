@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendNothingValueExceptionTests {

    @Test
    func nothingResultExceptionIsCatchableAsException() throws {
        let source = try diffCaseSource("kuu2915_kotlin_nothing_value_exception_catch.kt", file: #filePath)
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "NothingValueExceptionCatch",
                emit: .executable,
                outputPath: outputPath
            )
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "KotlinNothingValueException\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test
    func definitelyNullNullAssertionThrowsNullPointerException() throws {
        let source = try diffCaseSource("kuu4593_definitely_null_assertion_npe.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "DefinitelyNullNullAssertion",
            expected: "npe\n"
        )
    }

    @Test
    func definitelyNullNullAssertionMemberAccessThrowsNullPointerException() throws {
        let source = try diffCaseSource("kuu4593_definitely_null_assertion_member.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "DefinitelyNullNullAssertionMember",
            expected: "prop-npe\nsize-npe\nfun-npe\n"
        )
    }
}
