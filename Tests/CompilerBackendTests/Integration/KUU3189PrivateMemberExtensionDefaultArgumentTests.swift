import Testing

extension BundledStdlibExecutionTests {
    // Based on JetBrains Kotlin's codegen/box/defaultArguments/kt6382.kt.
    @Test
    func privateMemberExtensionDefaultArgumentRunsWithScopeReceiver() throws {
        try compileAndRunKotlin(
            """
            class A {
                fun run() = with("abc") { show() }
                private fun String.show(p: Boolean = false): String = getName() + this
                private fun getName() = "A"
            }

            fun main() {
                println(A().run())
            }
            """,
            expectedOutput: "Aabc\n",
            moduleName: "KUU3189PrivateMemberExtensionDefaultArgument"
        )
    }
}
