import Testing

@Suite(.serialized)
struct LocalClassOuterPropertyReferenceExecutionTests {
    @Test
    func boundPrivateSetterPropertyReferenceFromLocalClassRuns() throws {
        try compileAndRunKotlin(
            """
            class C {
                var value: String = "fail"
                    private set

                fun bar(): String {
                    class D { fun foo() = this@C::value }
                    val r = D().foo()
                    r.set("OK")
                    return r.get()
                }
            }
            fun main() { println(C().bar()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3380LocalClassOuterPropertyReference"
        )
    }
}
