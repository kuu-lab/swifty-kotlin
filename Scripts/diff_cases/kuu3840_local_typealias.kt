// KUU-3840: function-local typealiases (Kotlin localTypeAliases test):
// local aliases in type positions, constructor calls, callable references,
// supertype entries of anonymous objects, and aliases nested in local
// classes. Local type aliases are experimental on the JVM reference, so
// the reference run needs the language toggle.
// KOTLINC_FLAGS: -XXLanguage:+LocalTypeAliases -XXLanguage:+NestedTypeAliases

open class Generic<K>(val k: K) {
    companion object C {
        val prop: Int = 123
    }
    inner class Inner<K2>(val k2: K2)
}

fun testGeneral(): String {
    class Local2<T>(val p: T)

    open class Local {
        val p: String
            get() = "OK"

        typealias LocalTAtoLocal = Local
        typealias LocaTAtoLocal2<K> = Local2<K>
        typealias LocalTA2toLocal2 = Local2<String>

        fun test(): String {
            if (LocalTAtoLocal().p != "OK") return "FAIL1"
            if (LocaTAtoLocal2("OK").p != "OK") return "FAIL2"
            if (LocalTA2toLocal2("OK").p != "OK") return "FAIL3"
            return "OK"
        }
    }

    typealias TAtoLocal = Local
    typealias TAtoLocal2<K> = Local2<K>
    typealias TA2toLocal2 = Local2<String>

    typealias TAtoGeneric<K> = Generic<K>
    typealias TAtoInner<K, L> = Generic<K>.Inner<L>

    if (Local().test() != "OK") return "FAIL0"

    if (TAtoLocal().p != "OK") return "FAIL4"
    if (TAtoLocal2("OK").p != "OK") return "FAIL5"
    if (TA2toLocal2("OK").p != "OK") return "FAIL6"

    val callable = ::TAtoLocal
    if (callable().p != "OK") return "FAIL7"

    fun localFunc(): TAtoLocal = TAtoLocal()
    if (localFunc().test() != "OK") return "FAIL8"

    if (TAtoGeneric<String>("OK").k != "OK") return "FAIL9"
    val genericObj = Generic<Int>(42)
    if (genericObj.TAtoInner<Int, String>("OK").k2 != "OK") return "FAIL10"

    val anonObject = object : TAtoLocal() {}
    if (anonObject.test() != "OK") return "FAIL11"

    val anonObject2 = object : TAtoGeneric<String>("OK") {}
    if (anonObject2.k != "OK") return "FAIL12"

    val companion = TAtoGeneric
    if (companion.prop != 123) return "FAIL13"

    val typeRefToLocalTypeAliasInLocalClass: Local.LocalTAtoLocal = Local.LocalTAtoLocal()
    if (typeRefToLocalTypeAliasInLocalClass.p != "OK") return "FAIL14"

    return "OK"
}

abstract class A {
    abstract val p: String
}

fun testReturnTypeAsLocalTypeAlias(): A {
    typealias TA = String
    class B(override val p: TA) : A()
    return B("OK")
}

fun main() {
    println(testGeneral())
    println(testReturnTypeAsLocalTypeAlias().p)
}
