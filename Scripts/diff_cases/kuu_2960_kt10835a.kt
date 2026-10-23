// KUU-2960: the generic receiver lambda must preserve its receiver as the inner outer.
fun <T, R> with2(receiver: T, block: T.() -> R): R = receiver.block()

class Kt10835aX(val x: String) {
    open inner class Y {
        fun foo() = x
    }

    fun foo(s: String): String {
        var result = ""
        with2(Kt10835aX(s + x)) {
            val obj = object : Y() {}
            result = obj.foo()
        }
        return result
    }
}

fun main() {
    println(Kt10835aX("K").foo("O"))
}
