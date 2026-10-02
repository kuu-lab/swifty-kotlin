#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-851 regression: source-backed callable properties must dispatch
    /// through their interface getter for user implementations.
    @Test
    func testUserCallableImplementationsDispatchPropertiesThroughInterfaces() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable
            import kotlin.reflect.KProperty
            import kotlin.reflect.KType

            class CallableImpl(override val name: String) : KCallable<Int> {
                override val returnType: KType
                    get() = throw UnsupportedOperationException()
            }

            class PropertyImpl(override val name: String) : KProperty<Int> {
                override val returnType: KType
                    get() = throw UnsupportedOperationException()
            }

            fun main() {
                println(CallableImpl("callable-direct").name)
                val callable: KCallable<Int> = CallableImpl("callable-interface")
                println(callable.name)
                try {
                    callable.returnType
                    println("callable returnType did not throw")
                } catch (e: Throwable) {
                    println("callable returnType threw")
                }

                println(PropertyImpl("property-direct").name)
                val property: KProperty<Int> = PropertyImpl("property-interface")
                println(property.name)
                try {
                    property.returnType
                    println("property returnType did not throw")
                } catch (e: Throwable) {
                    println("property returnType threw")
                }
            }
            """,
            expectedOutput: [
                "callable-direct",
                "callable-interface",
                "callable returnType threw",
                "property-direct",
                "property-interface",
                "property returnType threw",
            ].joined(separator: "\n") + "\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// Runtime KProperty stubs (delegate `property:` arguments) register their
    /// KCallable getters through the runtime itable. `name` returns a Kotlin
    /// String, so the registered bridge must satisfy the flat-string sret ABI —
    /// a regression returning the raw handle instead corrupted the receiver's
    /// stack slot and made `Map.getValue`'s `property.name` lookup produce
    /// garbage keys ("Key <pointer> is missing in the map").
    @Test
    func testRuntimeKPropertyStubsDispatchNameThroughInterface() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KProperty

            class D {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): Int {
                    println(property.name)
                    return 1
                }
            }

            fun main() {
                val v: Int by D()
                println(v)
                val m: Map<String, Int> = mapOf("delegatedValue" to 42)
                val delegatedValue: Int by m
                println(delegatedValue)
            }
            """,
            expectedOutput: "v\n1\n42\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
