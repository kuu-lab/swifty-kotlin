#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ValueClassGenericBoxingTests {
    @Test(arguments: [true, false])
    func genericValueClassBoxesSurviveErasedBoundaries(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3624_generic_value_class_boxing.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU3624GenericValueClassBoxing",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
