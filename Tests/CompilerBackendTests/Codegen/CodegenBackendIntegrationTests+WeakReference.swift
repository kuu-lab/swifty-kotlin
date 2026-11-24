@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendWeakReferenceTests {
    @Test
    func testCodegenWeakReferenceGetReflectsClear() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference

        class Box(val n: Int)

        fun main() {
            val box = Box(42)
            val ref = WeakReference(box)
            println(ref.get()?.n)
            ref.clear()
            println(ref.get() == null)
            println(ref.get())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceClearReflectsNull",
            expected: "42\ntrue\nnull\n"
        )
    }

    @Test
    func testCodegenWeakReferenceClearsReturnedOrdinaryObjectAfterGC() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference

        class Foo(val x: Int)

        object GlobalHolder { val retained = Foo(9) }

        fun initializeGlobalHolder(): Int = GlobalHolder.retained.x

        fun weakValue(): WeakReference<Foo> = WeakReference(Foo(42))

        fun main() {
            val live = Foo(7)
            println(initializeGlobalHolder())
            val weak = weakValue()
            java.lang.System.gc()
            println(GlobalHolder.retained.x)
            println(live.x)
            println(weak.value == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceCollectsReturnedObject",
            expected: "9\n9\n7\ntrue\n"
        )
    }

    // (Member calls on a WeakReference<*>-typed reference hit an unrelated
    // kklib-route bound-check gap, so the star-projected handle only reads
    // `value`; the shared box is cleared through `second`.)
    @Test
    func testCodegenWeakReferenceValueReturnsReferentThenNull() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        fun main() {
            val first = WeakReference("x")
            val second = WeakReference("y")
            println(first.get())
            println(first.value)
            println(second.value)
            first.clear()
            println(first.get())
            println(first.value)
            println(second.get())
            val star: WeakReference<*> = second
            println(star.value)
            second.clear()
            println(star.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceValueReturnsReferent",
            expected: "x\nx\ny\nnull\nnull\ny\ny\nnull\n"
        )
    }

    @Test
    func testCodegenWeakReferencePreservesRuntimeStringReferent() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        fun main() {
            val s = "hello".toString()
            val w = WeakReference(s)
            println(w.value == s)
            println(w.value is String)
            println(w.value)
            println(w.get() == s)
            println(w.get() is String)
            println(w.get())
            w.clear()
            println(w.value == null)
            println(w.get() == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceRuntimeStringReferent",
            expected: "true\ntrue\nhello\ntrue\ntrue\nhello\ntrue\ntrue\n"
        )
    }

    @Test(arguments: [false, true])
    func testCodegenWeakReferenceImmediateAndTypedReferents(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.ref.WeakReference
        import kotlin.native.ref.value

        class Box(val n: Int)

        fun main() {
            println(WeakReference(0).value)
            println(WeakReference(42).value)
            println(WeakReference(-1).value)
            println(WeakReference(Int.MIN_VALUE).value)
            println(WeakReference(Int.MAX_VALUE).value)
            println(WeakReference(42L).value)
            println(WeakReference(-7L).value)
            println(WeakReference(Long.MAX_VALUE).value)
            println(WeakReference(false).value)
            println(WeakReference(true).value)
            println(WeakReference('z').value)
            println(WeakReference(1.5f).value)
            println(WeakReference(1.5).value)
            println(WeakReference("hello").value)

            val boxRef = WeakReference(Box(7))
            println(boxRef.value?.n)
            println(boxRef.get()?.n)

            val arrayRef = WeakReference(arrayOf(5, 9))
            println(arrayRef.value?.get(0))
            println(arrayRef.get()?.get(1))

            val first = WeakReference("first")
            val second = WeakReference("second")
            val star: WeakReference<*> = second
            println(star.value is String)
            println(star.value)
            first.clear()
            println(first.value)
            println(first.get())
            println(second.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WeakReferenceImmediateAndTypedReferents",
            expected: """
            0
            42
            -1
            -2147483648
            2147483647
            42
            -7
            9223372036854775807
            false
            true
            z
            1.5
            1.5
            hello
            7
            7
            5
            9
            true
            second
            null
            null
            second
            """ + "\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
