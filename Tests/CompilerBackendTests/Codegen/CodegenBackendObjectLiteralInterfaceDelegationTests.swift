#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct CodegenBackendObjectLiteralInterfaceDelegationTests {
    @Test(arguments: [true, false])
    func anonymousObjectDelegateExecutes(_ allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("anonymous_object_interface_delegation.kt"),
            expectedOutput: "hi\n",
            moduleName: "AnonymousObjectDelegation",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test func delegationPreservesOverridesPropertiesAndEnclosingCaptures() throws {
        try compileAndRunKotlin(
            diffCaseSource("anonymous_object_interface_delegation_members.kt"),
            expectedOutput: """
            42
            7
            11
            7
            9
            42
            9
            9
            9
            right delegate
            left delegate
            object init
            30
            20
            10
            1
            2
            3
            4
            5
            9
            12
            13
            34
            2
            text:x
            21
            text:y
            text:named

            """,
            moduleName: "AnonymousObjectDelegationMembers"
        )
    }
}
#endif
