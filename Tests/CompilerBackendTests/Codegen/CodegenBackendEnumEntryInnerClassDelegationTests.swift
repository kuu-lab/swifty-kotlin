#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct CodegenBackendEnumEntryInnerClassDelegationTests {
    @Test func innerClassDelegatesToContainingEnumEntry() throws {
        try compileAndRunKotlin(
            diffCaseSource("kuu_3672_enum_entry_inner_class_delegation.kt"),
            expectedOutput: "OK\n",
            moduleName: "KUU3672EnumEntryInnerClassDelegation"
        )
    }
}
#endif
