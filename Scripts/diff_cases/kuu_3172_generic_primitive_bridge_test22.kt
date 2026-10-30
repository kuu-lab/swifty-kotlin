// KUU-3172 regression adapted from Kotlin 2.4.20 bridges/test22.kt.
open class Base<T> {
    open fun foo(x: T): Int = 42
}

open class Derived : Base<Int>() {
    override fun foo(x: Int) = x
}

class Data(val s: String)

fun box(): String {
    val d = Derived()
    try {
        val x = (d as Base<Data>).foo(Data("zzz"))
        return "FAIL: $x"
    } catch (e: ClassCastException) {
        return "OK"
    }
}

fun main() {
    println(box())
}
