#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    // KUU-2268: preserve the pinned Kotlin case and exercise the exact ByteArray
    // reproducer through both stdlib routes and optimization levels.
    @Test(arguments: [false, true], [0, 2])
    func numericArrayIncrementMatchesPinnedKotlin(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        let source = try diffCaseSource("kuu_2268_numeric_array_increment.kt", file: #filePath)
        let syntheticCase = try #require(source.range(of: "\nfun byteArrayIncrementProducesTwo"))
        let upstreamOriginal = source[..<syntheticCase.lowerBound]
        #expect(FileFingerprint.sha256Hex(Data(upstreamOriginal.utf8))
                == "b9b067b4ab364d08ba4c6cf0196058a3eef0fcdbddef21f077c68718d711613e")

        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\nOK\nOK\n",
            moduleName: "KUU2268NumericArrayIncrement",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}
#endif
