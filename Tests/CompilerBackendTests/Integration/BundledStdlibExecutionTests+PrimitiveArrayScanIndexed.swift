import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testIntArrayScanIndexedFromSource() throws {
        try compileAndRunKotlin(
            try diffCaseSource("primitive_array_scan_indexed.kt", file: #filePath),
            expectedOutput: """
            1, 1, 2, 4
            0, 0, 1, 1
            1, 2, 2, 2
            7
            seed;seed|0:4;seed|0:4|1:-1;seed|0:4|1:-1|2:3
            """ + "\n",
            moduleName: "KUU1890IntArrayScanIndexedSource",
            allowDefaultStdlibLibrary: false
        )
    }
}
