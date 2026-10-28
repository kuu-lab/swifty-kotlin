#if canImport(Testing)
import CompilerBackend
import CompilerCore
import CompilerTestSupport
import Testing

@Suite(.serialized)
struct LocalClassInnerCapturedLocalExecutionTests {
    @Test
    func innerLocalClassReadsCapturedLocalThroughOuterInstance() throws {
        try compileAndRunKotlin(
            """
            fun box(): String {
                var s: Any? = null
                var log = ""
                for (t in arrayOf("1", "2", "3")) {
                    class C {
                        val y = t
                        inner class D {
                            fun foo() = "($y;$t)"
                        }
                    }
                    if (s == null) s = C()
                    log += (s as C).D().foo()
                }
                return log
            }
            fun main() { print(box()) }
            """,
            expectedOutput: "(1;1)(1;1)(1;1)",
            moduleName: "KUU3597InnerLocalCapture"
        )
    }

    @Test
    func outerLocalClassCapturesLocalUsedOnlyByInnerClass() throws {
        try compileAndRunKotlin(
            """
            fun box(): String {
                var s: Any? = null
                var log = ""
                for (t in arrayOf("1", "2", "3")) {
                    class C {
                        inner class D {
                            fun foo() = t
                        }
                    }
                    if (s == null) s = C()
                    log += (s as C).D().foo()
                }
                return log
            }
            fun main() { print(box()) }
            """,
            expectedOutput: "111",
            moduleName: "KUU3597InnerLocalCaptureOnly"
        )
    }
}
#endif
