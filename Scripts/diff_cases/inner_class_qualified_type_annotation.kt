// qualified inner-class type annotations keep the qualifier's type arguments
class Outer<V : Any>(val initial: V) {
    inner class Values(val x: Int) {
        fun read(): V = initial
    }
    fun accept(v: Outer<V>.Values): String = v.read().toString()
    fun exercise(): String {
        val v: Outer<V>.Values = Values(1)
        return accept(v)
    }
}
fun main() {
    println(Outer("hi").exercise())
    println(Outer(42).exercise())
}
