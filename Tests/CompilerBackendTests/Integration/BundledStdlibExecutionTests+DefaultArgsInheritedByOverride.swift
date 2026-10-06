import Testing

// KUU-655: an `override` inherits the *base* declaration's default
// parameter values even when the override itself declares none of its own.
// Before this fix, kswiftc rejected the class case with
// `KSWIFTK-SEMA-0002: No viable overload found for call.` and failed to
// link the interface case at all (undefined `_m$default` symbol -- a
// second, independent bug this fix also covers: an interface method's own
// default value expressions were never collected). See
// `Scripts/diff_cases/default_args_inherited_by_override.kt` for the full
// scenario set (including a three-level chain, a `by`-delegation
// forwarder, a generic interface base, and a diamond), cross-checked
// against real kotlinc.
extension BundledStdlibExecutionTests {
    @Test
    func testClassOverrideInheritsBaseDefaultArgument() throws {
        try compileAndRunKotlin(
            """
            open class A { open fun f(x: Int = 1) = "A$x" }
            class B : A() { override fun f(x: Int) = "B$x" }
            fun main() {
                val a: A = B()
                println(a.f())
                println(a.f(2))
                println(B().f())
                println(A().f())
            }
            """,
            expectedOutput: "B1\nB2\nB1\nA1\n",
            moduleName: "KUU655ClassOverrideDefaultArg"
        )
    }

    @Test
    func testInterfaceOverrideInheritsBaseDefaultArgument() throws {
        try compileAndRunKotlin(
            """
            interface I { fun m(x: Int = 5): String }
            class IC : I { override fun m(x: Int) = "IC$x" }
            fun main() {
                val i: I = IC()
                println(i.m())
                println(IC().m())
                println(IC().m(9))
            }
            """,
            expectedOutput: "IC5\nIC5\nIC9\n",
            moduleName: "KUU655InterfaceOverrideDefaultArg"
        )
    }
}
