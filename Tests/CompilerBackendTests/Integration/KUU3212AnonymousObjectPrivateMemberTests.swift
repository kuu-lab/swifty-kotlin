import Testing

extension BundledStdlibExecutionTests {
    // KUU-3212: a `private` member of an enclosing class is not a member of
    // an anonymous object that subclasses it, so a bare reference inside the
    // object resolves to the enclosing instance. The object's own same-named
    // inherited slot must not shadow it — both property reads and function
    // calls dispatch on `this@X`, printing "OK" instead of "inner".
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

    /// Boundary case: an inherited (non-private) member *is* in the object's
    /// member scope, so `tag()` dispatches on the object itself and reads its
    /// own `n`. Kotlin/JVM prints "inner"; this pins the opposite side of the
    /// same rule so the private-member fix does not overreach.
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
