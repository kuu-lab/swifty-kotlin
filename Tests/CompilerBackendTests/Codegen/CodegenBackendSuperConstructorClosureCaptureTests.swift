#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// Runtime regressions for Kotlin's `closures/captureInSuperConstructorCall` box cases.
@Suite
struct CodegenBackendSuperConstructorClosureCaptureTests {
    @Test(arguments: [
        """
        open class Base(val fn: () -> String)
        fun main() {
            val o = "O"
            class Local(k: String) : Base({ o + k })
            println(Local("K").fn())
        }
        """,
        """
        open class Base(val fn: () -> String)
        class Outer(val ok: String) {
            inner class Inner : Base({ ok })
        }
        fun main() { println(Outer("OK").Inner().fn()) }
        """,
        """
        open class Base(val fn: () -> String)
        class Outer(val ok: String) {
            inner class Inner : Base {
                constructor() : super({ ok })
            }
        }
        fun main() { println(Outer("OK").Inner().fn()) }
        """,
        """
        open class Base(val fn: () -> String)
        class Outer(val ok: String) {
            inner class Inner : Base({
                val callback = { ok }
                callback()
            })
        }
        fun main() { println(Outer("OK").Inner().fn()) }
        """,
        """
        open class Holder(val fn: () -> String)
        open class Wrapper(val holder: Holder)
        class Outer(val value: String) {
            inner class Inner : Wrapper(Holder({ value }))
        }
        fun main() { println(Outer("OK").Inner().holder.fn()) }
        """,
        """
        interface Callback { fun invoke(): String }
        open class Base(val callback: Callback)
        class Outer(val ok: String) {
            inner class Inner : Base(object : Callback {
                override fun invoke() = ok
            })
        }
        fun main() { println(Outer("OK").Inner().callback.invoke()) }
        """,
        """
        open class Base(val fn: () -> Char)
        fun make(value: Char): Base = object : Base({ value }) {}
        fun main() { println(if (make('K').fn() == 'K') "OK" else "FAIL") }
        """,
        """
        open class Base(val first: () -> String, val second: () -> String)
        fun main() {
            val x = "x"
            class Local(y: String) : Base({ x + y }, { y + x })
            val local = Local("y")
            println(if (local.first() == "xy" && local.second() == "yx") "OK" else "FAIL")
        }
        """,
        """
        open class Base(val fn: () -> String)
        fun main() {
            class Local(val ok: String) {
                inner class Inner : Base({ ok })
            }
            println(Local("OK").Inner().fn())
        }
        """,
    ])
    func capturesValuesAcrossSuperConstructorCallShapes(source: String) throws {
        try assertKotlinOutput(
            source,
            moduleName: "SuperConstructorClosureCapture",
            expected: "OK\n"
        )
    }

    @Test
    func inlineLambdaCapturesOuterReceiverFromSuperCall() throws {
        try assertKotlinOutput(
            """
            open class Base(val callback: () -> String)
            class Outer {
                val ok = "OK"
                inner class Inner : Base(
                    run {
                        val x = ok
                        { x }
                    }
                )
            }
            fun main() { println(Outer().Inner().callback()) }
            """,
            moduleName: "SuperConstructorInlineLambdaOuterCapture",
            expected: "OK\n"
        )
    }

    @Test
    func localAndConstructorParameterCaptureThroughInnerClass() throws {
        try assertKotlinOutput(
            """
            open class Base(val fn: () -> String)
            fun main() {
                val o = "O"
                class Local {
                    inner class Inner(k: String) : Base({ o + k })
                }
                println(Local().Inner("K").fn())
            }
            """,
            moduleName: "SuperConstructorNestedLocalCapture",
            expected: "OK\n"
        )
    }

    @Test
    func boundReferenceCapturesImplicitOuterReceiver() throws {
        try assertKotlinOutput(
            """
            abstract class Base(val fn: () -> String)
            class Outer {
                val ok = "OK"
                inner class Inner : Base(::ok)
            }
            fun main() { println(Outer().Inner().fn()) }
            """,
            moduleName: "SuperConstructorBoundOuterReference",
            expected: "OK\n"
        )
    }

    @Test
    func enumEntryInnerClassCapturesEnumEntryReceiver() throws {
        try assertKotlinOutput(
            """
            abstract class Base(val fn: () -> Test)
            enum class Test(val ok: String) {
                TEST("OK") {
                    inner class Inner : Base({ TEST })
                    override val base: Base get() = Inner()
                };
                abstract val base: Base
            }
            fun main() { println(Test.TEST.base.fn().ok) }
            """,
            moduleName: "SuperConstructorEnumEntryCapture",
            expected: "OK\n"
        )
    }

    @Test
    func superConstructorArgumentLambdaReadsOuterPropertyBeforeDelegation() throws {
        let source = """
        open class Outer(val ok: String) {
            inner class Inner : Outer {
                constructor() : super({ ok }())
            }
        }
        fun main() { println(Outer("K").Inner().ok) }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SuperConstructorOuterPropertyCapture",
            expected: "K\n"
        )
    }

    @Test
    func localFunctionCaptureInSuperCallPreservesCallableEnvironment() throws {
        let source = """
        open class Base(val fn: () -> String)
        fun make(): Base {
            val x = "O"
            fun localFn() = x
            class Local(y: String) : Base({ localFn() + y })
            return Local("K")
        }
        fun main() { println(make().fn()) }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SuperConstructorLocalFunctionCapture",
            expected: "OK\n"
        )
    }
}
#endif
