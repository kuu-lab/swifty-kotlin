import Testing

@Suite(.serialized)
struct KUU3521InterfaceDiamondTests {
    @Test
    func inheritedInterfaceOverrideResolvesDiamond() throws {
        try compileAndRunKotlin(
            """
            interface BK { fun foo(): String = "10" }
            interface KTrait: BK { override fun foo() = "30" }
            class A : BK, KTrait {}
            fun main() { println(A().foo()) }
            """,
            expectedOutput: "30\n",
            moduleName: "KUU3521InterfaceDiamond"
        )
    }
}
