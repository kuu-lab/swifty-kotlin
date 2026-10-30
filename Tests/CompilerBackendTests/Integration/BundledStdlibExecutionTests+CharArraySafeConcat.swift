@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func nullableCharArrayConcatPassesItsReceiver(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("chararray_concat_to_string_safe_call.kt", file: #filePath),
            expectedOutput: "hi\nnull\nok\ncustom\nnull\nx\n1\n",
            moduleName: "NullableCharArrayConcat",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
