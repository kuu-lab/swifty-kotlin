#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendPropertyDelegateEdgeCasesTests {

    @Test
    func testCodegenTrailingLambdaDelegatesAcrossPropertyScopes() throws {
        let source = """
        import kotlin.reflect.KProperty
        class MyLazy<T>(private val initializer: () -> T) {
            private var cached: Any? = null
            private var done: Boolean = false
            operator fun getValue(thisRef: Any?, property: KProperty<*>): T {
                if (!done) { cached = initializer(); done = true }
                @Suppress("UNCHECKED_CAST")
                return cached as T
            }
        }
        fun <T> myLazy(initializer: () -> T): MyLazy<T> = MyLazy(initializer)
        var evaluations = 0
        val top: String by MyLazy { val value = "top"; value }
        val evaluated: Int by myLazy { evaluations = evaluations + 1; evaluations }
        val parenthesizedCtor: String by MyLazy({ "parenthesized-ctor" })
        val parenthesizedFactory: String by myLazy({ "parenthesized-factory" })
        class Box(val prefix: String) {
            val member: String by myLazy { val value = prefix; value + "-member" }
        }
        fun local(prefix: String): String {
            val value: String by myLazy { val localValue = prefix; localValue + "-local" }
            return value
        }
        fun main() {
            println(top)
            println(evaluated)
            println(evaluated)
            println(evaluations)
            println(Box("member").member)
            println(local("capture"))
            println(parenthesizedCtor)
            println(parenthesizedFactory)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TrailingLambdaDelegatesAcrossScopes",
            expected:
                """
                top
                1
                1
                1
                member-member
                capture-local
                parenthesized-ctor
                parenthesized-factory
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value = lazyOf(42)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyOfValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesLazyBlockValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesDirectLazyCallValueRead() throws {
        let source = """
        fun main() {
            val value = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DirectLazyCallValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesLazyBlockCapturingOuterVariable() throws {
        let source = """
        fun main() {
            val base = 40
            val value = lazy { base + 2 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockCapturingOuterVariable",
            expected:
                """
                42
                """ + "\n"
        )
    }

    @Test
    func testCallableReferencesInConditionalLazyDelegates() throws {
        let source = """
        fun foo(): Int = 1
        fun bar(): Int = 2
        class Test(b: Boolean) {
            val test_1 by lazy { val a = if (b) { ::foo } else { ::bar }; a }
            val test_2 by lazy { val a = if (b) ::foo else ::bar; a }
            val test_3 by lazy { val a = when { b -> { ::foo } else -> { ::bar } }; a }
        }
        fun main() {
            println(Test(true).test_1())
            println(Test(false).test_1())
            println(Test(true).test_2())
            println(Test(false).test_2())
            println(Test(true).test_3())
            println(Test(false).test_3())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CallableReferencesInConditionalLazyDelegates",
            expected: "1\n2\n1\n2\n1\n2\n"
        )
    }

    @Test
    func testCodegenCompilesLazyDelegateCapturedByNestedLambda() throws {
        let source = """
        fun main() {
            val value by lazy { 42 }
            val read = { value }
            println(read())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyDelegateCapturedByNestedLambda",
            expected:
                """
                42
                """ + "\n",
            allowDefaultStdlibLibrary: false
        )
    }

    @Test
    func testCodegenCompilesExplicitlyTypedLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazyOf(99)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ExplicitlyTypedLazyOfValueRead",
            expected:
                """
                99
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateReturnsUnboxedInt() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x)
            println(x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateInt",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateReturnsString() throws {
        let source = """
        class StringProp {
            operator fun getValue(thisRef: Any?, property: Any?): String = "hello"
        }
        fun main() {
            val x by StringProp()
            println(x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateString",
            expected:
                """
                hello
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateReturnsBoolean() throws {
        let source = """
        class BooleanProp {
            operator fun getValue(thisRef: Any?, property: Any?): Boolean = true
        }
        fun main() {
            val x by BooleanProp()
            println(x)
            println(!x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateBoolean",
            expected:
                """
                true
                false
                """ + "\n"
        )
    }

    @Test
    func testMemberLazyDelegateCapturesEnclosingInstanceProperty() throws {
        let source = """
        class Foo(val label: String) {
            val x by lazy { label }
        }
        fun main() {
            val a = Foo("a")
            println(a.x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegateCapturesLabel",
            expected:
                """
                a
                """ + "\n"
        )
    }

    @Test
    func testMemberLazyDelegateBodyUsesTypedInstanceState() throws {
        let source = """
        class Foo {
            var count = 0
            fun next(): Int {
                count += 1
                return count
            }
            val x: Int by lazy { next() + count }
        }
        fun main() {
            val foo = Foo()
            println(foo.x)
            println(foo.x)
            println(foo.count)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegateUsesTypedInstanceState",
            expected:
                """
                2
                2
                1
                """ + "\n"
        )
    }

    @Test
    func testMemberLazyDelegateUsesPerInstanceStorage() throws {
        let source = """
        class Foo(val label: String) {
            val x by lazy { label }
        }
        fun main() {
            val a = Foo("a")
            val b = Foo("b")
            println(a.x)
            println(b.x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegatePerInstanceStorage",
            expected:
                """
                a
                b
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalProvideDelegateReturnsString() throws {
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val v: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
        }
        class StrFactory(private val v: String) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): StrDelegate = StrDelegate(v.uppercase())
        }
        fun main() {
            val name by StrFactory("hello")
            println(name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalProvideDelegateString",
            expected:
                """
                HELLO
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalProvideDelegateVarSetValueRoundTrips() throws {
        let source = """
        import kotlin.reflect.KProperty
        class IntBox(private var stored: Int) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = stored
            operator fun setValue(thisRef: Any?, property: KProperty<*>, newValue: Int) { stored = newValue }
        }
        class IntBoxFactory(private val initial: Int) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): IntBox = IntBox(initial)
        }
        fun main() {
            var counter by IntBoxFactory(10)
            println(counter)
            counter = 42
            println(counter)
            counter = counter + 1
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalProvideDelegateVarSetValue",
            expected:
                """
                10
                42
                43
                """ + "\n"
        )
    }

    @Test
    func testCodegenTopLevelProvideDelegateStillWorks() throws {
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val v: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
        }
        class StrFactory(private val v: String) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): StrDelegate = StrDelegate(v.uppercase())
        }
        val topName by StrFactory("hi")
        fun main() {
            println(topName)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelProvideDelegateStillWorks",
            expected:
                """
                HI
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberProvideDelegateUsesResolvedOperator() throws {
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val value: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = value
        }
        class StrFactory(private val value: String) {
            operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): StrDelegate =
                StrDelegate(value.uppercase())
        }
        class Holder {
            val name by StrFactory("member")
        }
        fun main() {
            println(Holder().name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberProvideDelegateResolvedOperator",
            expected:
                """
                MEMBER
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberCustomDelegatePrimitiveStillWorks() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Holder {
            val x by IntProp()
        }
        fun main() {
            val h = Holder()
            println(h.x)
            println(h.x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberDelegateIntStillWorks",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberObservableDelegateReportsChanges() throws {
        let source = """
        import kotlin.properties.Delegates

        class User {
            var name: String by Delegates.observable("initial") { _, old, new ->
                println("changed from $old to $new")
            }
        }

        fun main() {
            val u = User()
            u.name = "hello"
            println(u.name)
            u.name = "world"
            println(u.name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberObservableDelegate",
            expected:
                """
                changed from initial to hello
                hello
                changed from hello to world
                world
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberObservableDelegateFormatsIntValues() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter {
            var value: Int by Delegates.observable(1) { _, old, new ->
                println("obs:$old->$new")
            }
        }

        fun main() {
            val c = Counter()
            c.value = 2
            c.value = 5
            println(c.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberObservableDelegateIntValues",
            expected:
                """
                obs:1->2
                obs:2->5
                5
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberVetoableDelegateRejectsChanges() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter {
            var value: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
        }

        fun main() {
            val c = Counter()
            c.value = 5
            println(c.value)
            c.value = -1
            println(c.value)
            c.value += 3
            println(c.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberVetoableDelegate",
            expected:
                """
                5
                5
                8
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberDelegateCallbacksCaptureEnclosingInstance() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter(val label: String, val minimum: Int) {
            var callbackCount: Int = 0
            var observed: Int by Delegates.observable(1) { _, old, new ->
                callbackCount += 1
                println("$label:$old->$new:$callbackCount")
            }
            var guarded: Int by Delegates.vetoable(0) { _, _, new ->
                println("$label:check:$new")
                new >= minimum
            }
        }

        fun main() {
            val a = Counter("a", 2)
            val b = Counter("b", 5)
            a.observed = 3
            b.observed = 4
            println(a.callbackCount)
            println(b.callbackCount)
            a.guarded = 1
            a.guarded = 2
            println(a.guarded)
            b.guarded = 4
            b.guarded = 5
            println(b.guarded)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberDelegateCallbackCapture",
            expected:
                """
                a:1->3:1
                b:1->4:1
                1
                1
                a:check:1
                a:check:2
                2
                b:check:4
                b:check:5
                5
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberNotNullDelegateRoundTrips() throws {
        let source = """
        import kotlin.properties.Delegates

        class Box {
            var value: String by Delegates.notNull()
        }

        fun main() {
            val b = Box()
            b.value = "abc"
            println(b.value)
            b.value = "def"
            println(b.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberNotNullDelegate",
            expected:
                """
                abc
                def
                """ + "\n"
        )
    }

    @Test
    func testCodegenTopLevelObservableAndVetoableDelegates() throws {
        let source = """
        import kotlin.properties.Delegates

        var topName: String by Delegates.observable("t0") { _, old, new -> println("top $old->$new") }
        var topCount: Int by Delegates.vetoable(1) { _, _, new -> new > 0 }
        var topLate: Int by Delegates.notNull()

        fun main() {
            topName = "t1"
            println(topName)
            topCount = 9
            println(topCount)
            topCount = -5
            println(topCount)
            topLate = 3
            println(topLate)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelStdlibDelegates",
            expected:
                """
                top t0->t1
                t1
                9
                9
                3
                """ + "\n"
        )
    }

    @Test
    func testCodegenObjectLiteralLazyDelegateBothReceivers() throws {
        let source = """
        fun main() {
            val o = object {
                val x: Int by lazy { 42 }
                fun show(): Int = x
            }
            println(o.x)
            println(o.show())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralLazyDelegateBothReceivers",
            expected:
                """
                42
                42
                """ + "\n"
        )
    }

    @Test
    func testCodegenObjectLiteralCustomDelegateReadWriteCompound() throws {
        let source = """
        import kotlin.reflect.KProperty

        class IntBox(var v: Int) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = v
            operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
                v = value
            }
        }

        fun main() {
            val m = object {
                var count: Int by IntBox(7)
                fun read(): Int = count
                fun bump() { count += 1 }
            }
            println(m.count)
            m.count = 8
            println(m.count)
            println(m.read())
            m.bump()
            println(m.count)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralCustomDelegateReadWriteCompound",
            expected:
                """
                7
                8
                8
                9
                """ + "\n"
        )
    }

    @Test
    func testCodegenObjectLiteralLazyDelegateCapturesOuterLocal() throws {
        let source = """
        fun main() {
            val base = 20
            val captured = object {
                val x: Int by lazy { base + 1 }
                fun show(): Int = x
            }
            println(captured.x)
            println(captured.show())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ObjectLiteralLazyDelegateCapturesOuterLocal",
            expected:
                """
                21
                21
                """ + "\n"
        )
    }
}
#endif
