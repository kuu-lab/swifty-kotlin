// KUU-3840: nested typealiases declared inside a class body resolve like
// Kotlin's NestedTypeAliases feature (stable in 2.4): constructor calls,
// type positions, qualified access, and generic substitutions.

class Local2<T>(val p: T)

open class Outer {
    typealias LocalTAtoOuter = Outer
    typealias LocalTAtoLocal2<K> = Local2<K>
    typealias FixedLocal2 = Local2<String>

    fun test(): String {
        if (LocalTAtoOuter().probe() != "OK") return "FAIL1"
        if (LocalTAtoLocal2("OK").p != "OK") return "FAIL2"
        if (FixedLocal2("OK").p != "OK") return "FAIL3"
        return "OK"
    }

    fun probe(): String = "OK"
}

fun main() {
    println(Outer().test())
    val x: Outer.LocalTAtoOuter = Outer.LocalTAtoOuter()
    println(x.probe())
    val y: Outer.LocalTAtoLocal2<Int> = Outer.LocalTAtoLocal2(7)
    println(y.p)
}
