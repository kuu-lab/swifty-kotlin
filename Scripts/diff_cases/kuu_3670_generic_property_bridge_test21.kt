// KUU-3670 regression adapted from Kotlin 2.4.20 bridges/test21.kt.
open class Base<T> {
    open var x: T? = null
}

open class Derived : Base<String>()

class Data(val x: Int)

fun garble(d: Derived) {
    (d as Base<Data>).x = Data(42)
}

fun box(): String {
    val d = Derived()
    garble(d)
    try {
        val x = d.x
        return "FAIL: ${x?.length}"
    } catch (e: ClassCastException) {
        return "OK"
    }
}

fun main() {
    println(box())
}
