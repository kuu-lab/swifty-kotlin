@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testSystemArraycopyFromBundledArtifact(optimized: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("system_arraycopy.kt", file: #filePath),
            expectedOutput: """
            [a, b, one, two, e]
            [7, 8]
            [1, 1, 2, 3, 4]
            zero-length-ok
            range-error
            negative-length-error
            store-error
            [copied, kept]
            [8, 9, 0, 0]
            primitive-store-error
            null-error

            """,
            moduleName: "KUU2223SystemArraycopy",
            allowDefaultStdlibLibrary: true,
            optLevel: optimized ? .O2 : .O0
        )
    }
}
