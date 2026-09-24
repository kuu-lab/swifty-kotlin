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
}
#endif
