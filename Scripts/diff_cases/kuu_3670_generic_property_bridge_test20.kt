// KUU-3670 regression adapted from Kotlin 2.4.20 bridges/test20.kt.
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
