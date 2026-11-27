import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testAnonymousObjectResolvesEnclosingPrivateMember() throws {
        try compileAndRunKotlin(
            """
            open class X(private val n: String) {
                private fun tag(): String = n
                fun prop(): String = object : X("inner") { fun print() = n }.print()
                fun call(): String = object : X("inner") { fun print() = tag() }.print()
            }
            fun main() {
                val x = X("OK")
                println(x.prop())
                println(x.call())
            }
            """,
            expectedOutput: "OK\nOK\n",
            moduleName: "KUU3212AnonymousObjectPrivateMember"
        )
    }

    @Test
    func testAnonymousObjectInheritedPublicMemberStillWins() throws {
        try compileAndRunKotlin(
            """
            open class X(val n: String) {
                fun tag(): String = n
                fun foo(): String = object : X("inner") { fun print() = tag() }.print()
            }
            fun main() { println(X("OK").foo()) }
            """,
            expectedOutput: "inner\n",
            moduleName: "KUU3212AnonymousObjectPublicMember"
        )
    }
}
