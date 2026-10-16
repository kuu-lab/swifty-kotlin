import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [0, 2])
    func testSuspendSAMFunctionValueAdaptation(
        optimization: Int
    ) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2434_suspend_sam_function_values.kt", file: #filePath),
            expectedOutput: "OK\nOK\n",
            moduleName: "KUU2434SuspendSAMAdaptation",
            allowDefaultStdlibLibrary: true,
            optLevel: optimization == 0 ? .O0 : .O2
        )
    }
}
