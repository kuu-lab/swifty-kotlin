// KUU-3670: a `val s: T` read through a wrongly-parameterized generic base
// must checkcast the erased getter result at the claim site
// (kotlin/testData/codegen/box/bridges/test20.kt).
open class A<T> {
    val s: T = "zzz" as T
}

interface C {
    val s: String
}

class B : C, A<String>()

class Data(val x: Int)

fun box(): String {
    val b = B()
    try {
        val s = (b as A<Data>).s
        return "FAIL: ${s.x}"
    } catch (e: ClassCastException) {
        return "OK"
    }
}

fun main() {
    println(box())
}
