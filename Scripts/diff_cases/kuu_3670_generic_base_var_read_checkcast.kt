// KUU-3670: a raw write through a wrongly-parameterized generic base stores
// the foreign value; the typed `var x: T?` read must checkcast the erased
// getter result (kotlin/testData/codegen/box/bridges/test21.kt).
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
