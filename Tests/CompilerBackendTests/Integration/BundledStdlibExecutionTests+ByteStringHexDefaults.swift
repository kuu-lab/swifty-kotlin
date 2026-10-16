@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testByteStringHexDefaultBridgesDispatchWithoutOptIn(
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_bytestring_hex_default_bridges.kt", file: #filePath),
            expectedOutput: "ab12cdef\n12cdef\nab12\n12cd\n12cd\n\n0\nab12\nhex-range-invalid-order\nhex-default-rejects-separator\n",
            moduleName: "KUU2621ByteStringHexDefaultBridges",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == 0 ? .O0 : .O2,
            // Source injection currently reports platform-type warnings from
            // the bundled stdlib; keep the precompiled artifact lane clean.
            requireNoCompilerDiagnostics: allowDefaultStdlibLibrary
        )
    }
}
