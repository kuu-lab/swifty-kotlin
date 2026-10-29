import Testing

@Suite(.serialized)
struct DelegatedExtensionPropertyExecutionTests {
    @Test func testTopLevelExtensionDelegateLinksAndReceivesExtensionReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty

        class A
        class Delegate {
            operator fun getValue(thisRef: A, property: KProperty<*>): Int = 1
        }

        val A.prop: Int by Delegate()

        fun main() {
            println(A().prop)
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "1\n",
            moduleName: "KUU2132TopLevelExtensionDelegate"
        )
    }

    @Test func testExtensionDelegateCanReferenceReceiverDeclaredLater() throws {
        let source = """
        import kotlin.reflect.KProperty

        class Delegate {
            operator fun getValue(thisRef: A, property: KProperty<*>): Int = 1
        }

        val A.prop: Int by Delegate()

        class A

        fun main() {
            println(A().prop)
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "1\n",
            moduleName: "KUU2132LateReceiverExtensionDelegate"
        )
    }

    @Test func testDelegatedPropertyReferencesCoverBoundAndSmartCastReceivers() throws {
        let source = """
        class C(val x: String)

        val x = "O"
        val y by ::x
        val z by C("K")::x

        class A {
            var x: String = "start"
        }

        val anyA: Any = A()

        class CastDelegate {
            var y by (anyA as A)::x
        }

        class ConstructorParameterDelegate(c: C) {
            val x by c::x
        }

        fun smartCastDelegate(a: Any): String {
            if (a !is A) return "FAIL 0: $a"
            class LocalDelegate {
                var y by a::x
            }
            val delegate = LocalDelegate()
            if (delegate.y != "start") return "FAIL 1: ${delegate.y}"
            delegate.y = "K"
            return "O" + a.x
        }

        fun box(): String {
            val castDelegate = CastDelegate()
            if (castDelegate.y != "start") return "FAIL 2: ${castDelegate.y}"
            castDelegate.y = "K"
            val castResult = "O" + (anyA as A).x
            val smartCastResult = smartCastDelegate(A())
            val referenced = y + z
            val constructorParameter = ConstructorParameterDelegate(C("OK")).x
            return if (castResult + smartCastResult + referenced + constructorParameter == "OKOKOKOK") "OK" else "FAIL"
        }

        fun main() {
            println(box())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU2132PropertyReferenceDelegateReceivers"
        )
    }

    @Test func testMemberExtensionDelegateCanReferenceReceiverProperty() throws {
        let source = """
        class B(val prop: String) {
            val B.alias: String by ::prop
        }

        fun box(): String {
            val sameTypeResult = with(B("OK")) { B("fail").alias }
            return if (sameTypeResult == "OK") "OK" else "FAIL"
        }

        fun main() {
            println(box())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU2132MemberExtensionReceiverPropertyDelegate"
        )
    }

    @Test func testDelegatesToConstantPropertyReferences() throws {
        let source = """
        var sideEffect = "Fail"

        object Property {
            init {
                sideEffect = "OK"
            }

            const val PROPERTY_VALUE: String = "O"
        }

        const val TOP_LEVEL_PROPERTY_VALUE: String = "K"

        val value1: String by Property::PROPERTY_VALUE
        val value2: String by ::TOP_LEVEL_PROPERTY_VALUE

        fun box(): String {
            if (sideEffect != "OK") return "Object initialization failed"
            return value1 + value2
        }

        fun main() {
            println(box())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU2132ConstantPropertyReferenceDelegate"
        )
    }

    @Test func testCustomPropertyReferenceDelegateOperators() throws {
        let source = """
        var x: String
            get() = throw Exception("x's getter should not be called")
            set(_) { throw Exception("x's setter should not be called") }

        var y: String by ::x
        var storage = "Fail"
        operator fun Any.getValue(thisRef: Any?, property: Any?): String = storage
        operator fun Any.setValue(thisRef: Any?, property: Any?, value: String) { storage = value }

        fun box(): String {
            y = "OK"
            return y
        }

        fun main() {
            println(box())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU2132CustomPropertyReferenceDelegate"
        )
    }

    @Test func testCompanionOpenAndBoundPropertyReferenceDelegates() throws {
        let source = """
        class Z(var x: String = "OK")

        operator fun Z.getValue(thisRef: Any?, property: Any?): Z = this
        operator fun Z.setValue(thisRef: Any?, property: Any?, value: Z) { this.x = value.x }

        interface WithCompanion {
            companion object {
                val instance: Z by Z()
                var y by instance::x
            }
        }

        object WithObject {
            val instance: Z by Z()
            val y by instance::x
        }

        class D {
            var y: String = "initial"
        }

        class E

        class BoundExtensionDelegate {
            val d = D()
            var E.x: String by d::y
        }

        val String.foo: String
            get() = this

        abstract class Base {
            abstract val x: String
            val y by x::foo
        }

        var storage = "OK"

        class Derived : Base() {
            override var x: String
                get() = storage
                set(value) { storage = value }
        }

        fun box(): String {
            WithCompanion.y = "C"
            val receiver = E()
            val boundResult = with(BoundExtensionDelegate()) {
                receiver.x = "B"
                receiver.x
            }
            val result = WithCompanion.y + WithObject.y + Derived().y + boundResult
            return if (result == "COKOKB") "OK" else result
        }

        fun main() {
            println(box())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\n",
            moduleName: "KUU2132CompanionOpenBoundPropertyReferenceDelegate"
        )
    }

    @Test func testMemberExtensionDelegateLinksAndReceivesExtensionReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty

        class Delegate {
            operator fun getValue(thisRef: F.A, property: KProperty<*>): Int = 1
        }

        class F {
            val A.prop: Int by Delegate()

            class A

            fun value(): Int = A().prop
        }

        fun main() {
            println(F().value())
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "1\n",
            moduleName: "KUU2132MemberExtensionDelegate"
        )
    }

    @Test func testSameNamedExtensionDelegatesHaveSeparateStorage() throws {
        let source = """
        open class C
        object O : C()
        object K : C()

        class Delegate(private val value: String) {
            operator fun getValue(thisRef: C, property: Any): String = value
        }

        val O.prop by Delegate("O")
        val K.prop by Delegate("K")

        fun main() {
            print(O.prop + K.prop)
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK",
            moduleName: "KUU2132SameNamedExtensionDelegates"
        )
    }

    @Test func testDelegatedExtensionPropertyCanUsePropertyReferenceAsDelegate() throws {
        let source = """
        val x: String.() -> String = { this }
        val String.y: String.() -> String
            get() = { this + this@y }

        val String.c: String.() -> String by String::y
        val String.d: (String) -> String by String::y

        fun main() {
            val a: (String) -> String by ::x
            val b: String.() -> String by ::x
            print(a("1") + "2".b() + "4".c("3") + "6".d("5"))
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "123456",
            moduleName: "KUU2132DelegatedByExtensionPropertyReference"
        )
    }

    @Test func testMemberExtensionDelegateCanUseMutablePropertyReference() throws {
        let source = """
        class A { var x: String = "Fail" }

        class C {
            var A.y: String by A::x

            fun setAndRead(a: A): String {
                a.y = "OK"
                return a.y
            }
        }

        fun main() {
            print(C().setAndRead(A()))
        }
        """

        try compileAndRunKotlin(
            source,
            expectedOutput: "OK",
            moduleName: "KUU2132MemberExtensionPropertyReference"
        )
    }
}
