// KUU-3937: inside a member function, an expected supertype pins the
// constructor's own class type parameter (PersistentOrderedSet.add shape).
interface PS<E> {
    fun first(): Any?
}

class POS<E>(val a: Any?, val b: Any?) : PS<E> {
    fun add(element: E): PS<E> = POS(element, element)
    override fun first(): Any? = a
}

fun main() {
    val s = POS<Int>(1, 2)
    println(s.add(3).first())
}
