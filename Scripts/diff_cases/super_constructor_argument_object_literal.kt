// Kotlin-valid object members in an inner class super constructor argument.
interface Callback { fun value(): String }
open class Base(val callback: Callback)

open class Outer(val x: String) {
    open inner class Inner

    inner class Nested : Base(object : Outer.Inner(), Callback {
        override fun value() = x
    })

    inner class Simple : Base(object : Callback {
        override fun value() = x
    })

    fun makeCallback(): Callback = object : Outer.Inner(), Callback {
        override fun value() = x
    }
}

fun box(): String {
    val outer = Outer("OK")
    return if (outer.Nested().callback.value() == "OK"
        && outer.Simple().callback.value() == "OK"
        && outer.makeCallback().value() == "OK") "OK" else "FAIL"
}

fun main() { println(box()) }
