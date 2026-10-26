import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKUU3448ArrayHOFCompleteness(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3448_array_hof.kt", file: #filePath),
            expectedOutput: "KUU-3448 array HOFs passed\n",
            moduleName: "KUU3448ArrayHOFCompleteness",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
