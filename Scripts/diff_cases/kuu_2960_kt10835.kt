// KUU-2960: an object extending an inner class uses the `with` receiver as its outer.
class Kt10835X(val x: String) {
    open inner class Y {
        fun foo() = x
    }

    fun foo(s: String): String {
        with(Kt10835X(s + x)) {
            val obj = object : Y() {}
            return obj.foo()
        }
    }
}

fun main() {
    println(Kt10835X("K").foo("O"))
}
