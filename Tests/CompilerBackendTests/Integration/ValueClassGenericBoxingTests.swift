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

    @Test
    func genericOverrideBoxesReferenceBackedValueClassReturn() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3681_generic_override_value_class_return.kt", file: #filePath),
            expectedOutput: "true\nO\n",
            moduleName: "KUU3681GenericOverrideValueClassReturn",
            allowDefaultStdlibLibrary: true
        )
    }

    /// KUU-3771: `IC<T:Int>(42).i` regressed to a runtime
    /// `KSWIFTK-LINK-0003` panic when the KUU-3670 erased-generic claim
    /// checkcast observed the payload re-tagged as the value class. The
    /// property read must keep the raw payload representation.
    @Test
    func genericValueClassUnderlyingPropertyReadClaimsPayload() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3771_generic_value_class_erased_read.kt", file: #filePath),
            expectedOutput: "42\n7\n43\n9\n9\nnull\n42\n11\n",
            moduleName: "KUU3771GenericValueClassErasedRead",
            allowDefaultStdlibLibrary: true
        )
    }
}
#endif
