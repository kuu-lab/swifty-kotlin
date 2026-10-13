#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendRangeEdgeCasesTests {

    @Test
    func testCodegenLongRangeFirstAndLastOrNull() throws {
        let source = """
        fun main() {
            println((1L..5L).firstOrNull())
            println((1L..5L).lastOrNull())
            println((10L..1L).firstOrNull())
            println((10L..1L).lastOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LongRangeFirstLastOrNull",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == """
                    1
                    5
                    null
                    null
                    """ + "\n"
            )
        }
    }
}
#endif
