@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testByteStringIndexOfDefaultBridgesDispatch(
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_indexof_default_bridges.kt", file: #filePath),
            expectedOutput: "1\n2\n1\n-1\n-1\n0\n0\n",
            moduleName: "KUU2618ByteStringIndexOfDefaultBridges",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == 0 ? .O0 : .O2,
            requireNoCompilerDiagnostics: allowDefaultStdlibLibrary
        )
    }
}
