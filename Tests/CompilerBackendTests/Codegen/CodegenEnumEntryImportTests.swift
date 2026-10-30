@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenEnumEntryImportTests {
    @Test(arguments: [false, true], [0, 2])
    func wildcardImportAcrossFilesPrintsEntriesAndExhaustiveWhen(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        try withTemporaryFiles(contents: [
            "package tokens\nenum class Kind { PLUS, MINUS }",
            """
            import tokens.Kind.*
            fun main(){println(PLUS);println(when(PLUS){PLUS->3;MINUS->-3})}
            """,
        ]) { paths in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("consumer").path
            let options = CompilerOptions(
                moduleName: "EnumEntryWildcardImport",
                inputs: paths,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: useArtifact ? try testStdlibArtifactPath() : nil,
                allowDefaultStdlibLibrary: false
            )
            #expect(options.includeStdlib == !useArtifact)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "PLUS\n3\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
