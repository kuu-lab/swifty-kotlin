@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testKtorIOSourceByteArrayDefaultBridges(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        // Executes Source.readAtMostTo$default and SourcesKt.readTo$default through omitted Kotlin arguments.
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_source_bytearray_default_bridges.kt", file: #filePath),
            expectedOutput: "3:10,20,30,99\n-1:10,20,30,99\n3:99,99,1,2,3\n2:4,5,99,99\n7,8\n99,99,11,12,13,14\n21,22,23,99,99\neof:41,42,0\nbounds:IndexOutOfBoundsException\natMostOrder:IllegalArgumentException\natMostUpper:IndexOutOfBoundsException\natMostLower:IndexOutOfBoundsException\nreadToOrder:IllegalArgumentException\nreadToLower:IndexOutOfBoundsException\nreadToUpper:IndexOutOfBoundsException\n",
            moduleName: "KtorIOSourceByteArrayDefaultBridges",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
