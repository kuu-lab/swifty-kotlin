#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func indexedIntegerArraysWrapAtTheirDeclaredWidth(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        let source = try diffCaseSource("kuu_3096_indexed_integer_array_overflow.kt", file: #filePath)
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU3096IndexedIntegerArrayOverflow",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}
#endif
