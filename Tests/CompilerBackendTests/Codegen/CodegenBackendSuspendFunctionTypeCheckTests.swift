#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSuspendFunctionTypeCheckTests {
    @Test
    func testIsAndCastsCheckSuspendMarkerAndFunctionArity() throws {
        let source = """
        @Suppress("CANNOT_CHECK_FOR_ERASED")
        fun main() {
            val suspendedZero: suspend () -> Int = { 5 }
            val plainZero: () -> Int = { 6 }
            val suspendedOne: suspend (Int) -> Int = { it + 1 }
            val erasedSuspended: Any = suspendedZero
            val erasedPlain: Any = plainZero
            val erasedWrongArity: Any = suspendedOne

            println(erasedSuspended is suspend () -> Int)
            println(erasedPlain is suspend () -> Int)
            println(erasedWrongArity is suspend () -> Int)
            println((erasedSuspended as? suspend () -> Int) != null)
            println((erasedPlain as? suspend () -> Int) == null)
            println((erasedSuspended as? () -> Int) == null)
            println((erasedPlain as? () -> Int) != null)
            println((erasedSuspended as? Function1<*, *>) != null)

            try {
                val invalid: suspend () -> Int = erasedPlain as suspend () -> Int
                println("unexpected cast: " + invalid)
            } catch (error: ClassCastException) {
                println("caught cast")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SuspendFunctionTypeChecks",
            expected:
                """
                true
                false
                false
                true
                true
                true
                true
                true
                caught cast
                """
                + "\n"
        )
    }

    @Test
    func testKSuspendFunctionChecksEraseToKFunctionClassifier() throws {
        let source = """
        import kotlin.reflect.KCallable
        import kotlin.reflect.KFunction
        import kotlin.reflect.KFunction1
        import kotlin.reflect.KSuspendFunction0
        import kotlin.reflect.KSuspendFunction1
        import kotlin.reflect.KSuspendFunction2

        suspend fun foo(x: Int): Int = x
        fun bar(x: Int): Int = x * 2

        fun main() {
            // KUU-3841: KFunctionN/KSuspendFunctionN have no distinct runtime
            // class on the JVM, so `is` checks erase to the KFunction
            // classifier — every callable reference answers true regardless
            // of arity or suspend-ness, while a plain lambda answers false.
            val f: suspend (Int) -> Int = ::foo
            println(f is KSuspendFunction1<*, *>)
            println(f is KSuspendFunction0<*>)
            println(f is KSuspendFunction2<*, *, *>)
            println(f is KFunction1<*, *>)
            println(f is KFunction<*>)
            println(f is KCallable<*>)

            val plain: (Int) -> Int = ::bar
            println(plain is KFunction1<*, *>)
            println(plain is KSuspendFunction1<*, *>)

            val erased: Any = ::foo
            println(erased is KSuspendFunction1<*, *>)
            println(erased is KFunction1<*, *>)

            val lambda: suspend (Int) -> Int = { it }
            println(lambda is KSuspendFunction1<*, *>)
            println(lambda is KFunction1<*, *>)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KSuspendFunctionTypeChecks",
            expected:
                """
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                false
                false
                """
                + "\n"
        )
    }

    @Test
    func testKSuspendFunctionCastsMembersAndInvocation() throws {
        let source = """
        import kotlin.reflect.KFunction1
        import kotlin.reflect.KSuspendFunction1
        import kotlinx.coroutines.runBlocking

        suspend fun foo(x: Int): Int = x + 1

        fun main() {
            val g: KSuspendFunction1<Int, Int> = ::foo
            println(g.name)
            println(runBlocking { g(5) })

            val f: suspend (Int) -> Int = ::foo
            println((f as KSuspendFunction1<*, *>).name)
            println((f as? KFunction1<*, *>) != null)
            println((f as? KSuspendFunction1<*, *>) != null)
            val lambda: suspend (Int) -> Int = { it }
            try {
                lambda as KSuspendFunction1<*, *>
                println("unexpected cast")
            } catch (error: ClassCastException) {
                println("caught cast")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KSuspendFunctionCastsAndInvoke",
            expected:
                """
                foo
                6
                foo
                true
                true
                caught cast
                """
                + "\n"
        )
    }
}
#endif
