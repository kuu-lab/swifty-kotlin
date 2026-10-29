#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct CodegenBackendObjectLiteralInterfaceDelegationTests {
    @Test func nestedMemberInterfaceDelegateExecutes() throws {
        try compileAndRunKotlin(
            diffCaseSource("object_literal_member_nested_interface_delegation.kt"),
            expectedOutput: "1\n",
            moduleName: "ObjectLiteralNestedInterfaceDelegation"
        )
    }

    @Test func funInterfaceLambdaDelegationExecutes() throws {
        try compileAndRunKotlin(
            """
            fun interface F { fun f(): String }
            object F1 : F by { "OK" } {
                val marker: Int = 1
            }
            fun main() {
                println(F1.f())
                println(F1.marker)
            }
            """,
            expectedOutput: "OK\n1\n",
            moduleName: "FunInterfaceLambdaDelegation"
        )
    }

    @Test(arguments: [true, false])
    func anonymousObjectDelegateExecutes(_ allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("anonymous_object_interface_delegation.kt"),
            expectedOutput: "hi\n",
            moduleName: "AnonymousObjectDelegation",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func propertyInitializersKeepObjectInterfaceDelegation(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            diffCaseSource("object_interface_delegation_property_initializers.kt"),
            expectedOutput: "delegate\ndelegate\ndelegate\ndelegate\nproperty delegate\nordinary\n",
            moduleName: "ObjectInterfaceDelegationPropertyInitializers",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
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
