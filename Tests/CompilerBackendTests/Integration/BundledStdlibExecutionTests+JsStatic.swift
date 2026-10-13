import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testJsStaticCompanionCallRemainsAvailableOnNativeTarget() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)

            class StaticHolder {
                companion object {
                    @kotlin.js.JsStatic
                    fun message(): String = "companion"
                }
            }

            fun main() {
                println(StaticHolder.message())
            }
            """,
            expectedOutput: "companion\n",
            moduleName: "KUU1607JsStaticNativeMember"
        )
    }

    @Test
    func testExperimentalJsStaticMarkerUseInObjectRemainsOrdinaryKotlinMember() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsStatic::class)

            object JsHolder {
                @kotlin.js.ExperimentalJsStatic
                fun message(): String = "marker"
            }

            fun main() {
                println(JsHolder.message())
            }
            """,
            expectedOutput: "marker\n",
            moduleName: "KUU1607JsStaticMarkerOnly"
        )
    }
}
