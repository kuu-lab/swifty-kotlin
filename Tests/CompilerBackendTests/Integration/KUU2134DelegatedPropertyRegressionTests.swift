@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU2134DelegatedPropertyRegressionTests {
    @Test
    func singletonEnumSideEffectsAndErasedGenericReturns() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KProperty

            object Store {
                private val map = mutableMapOf<Pair<Any?, KProperty<*>>, String?>()
                operator fun getValue(thisRef: Any?, property: KProperty<*>): String? = map[thisRef to property]
                operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String?) {
                    map[thisRef to property] = value
                }
            }

            object O { var s: String? by Store }

            var initialized = false
            enum class E { X; companion object { init { initialized = true } } }
            operator fun Any?.getValue(x: Any?, y: Any?): String = throw RuntimeException()
            val result by E.X

            class Delegate<T>(var inner: T) {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): T = inner
                operator fun setValue(thisRef: Any?, property: KProperty<*>, value: T) { inner = value }
            }
            val delegate = Delegate("initial")
            val nullableDelegate = Delegate<String?>(null)
            class Owner {
                var value: String by delegate
                val nullableValue: String? by nullableDelegate
            }

            fun main() {
                O.s = "OK"
                println(O.s!!)
                println(if (initialized) "OK" else "FAIL")

                val owner = Owner()
                (delegate as Delegate<Int>).inner = 10
                println(try { owner.value; "NO CCE" } catch (e: ClassCastException) { "CCE" })
                (delegate as Delegate<String?>).inner = null
                println(try { owner.value; "NO CCE" } catch (e: ClassCastException) { "CCE" })
                println(owner.nullableValue ?: "NULL")
            }
            """,
            expectedOutput: "OK\nOK\nCCE\nCCE\nNULL\n",
            moduleName: "KUU2134DelegatedProperties",
            allowDefaultStdlibLibrary: true,
            optLevel: .O0
        )
    }
}
