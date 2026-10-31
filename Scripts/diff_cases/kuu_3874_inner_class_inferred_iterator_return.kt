// KUU-3874: `for (x in expr)` failed SEMA-0002 when the iterable is a
// generic class whose inferred `iterator()` return type is an inner class.
// The inferred return type dropped the captured enclosing type argument,
// so member calls on the returned iterator failed to bind.
class G<T>(private val s: List<T>) : Iterable<T> {
    inner class It(private val it: Iterator<T>) : Iterator<T> {
        override fun hasNext() = it.hasNext()
        override fun next() = it.next()
    }
    override fun iterator() = It(s.iterator())
}
class S<T>(private val items: List<T>) : Sequence<T> {
    inner class Sit(private val it: Iterator<T>) : Iterator<T> {
        override fun hasNext() = it.hasNext()
        override fun next() = it.next()
    }
    override fun iterator() = Sit(items.iterator())
}
fun main() {
    for (e in G(listOf("a", "b"))) { println(e) }
    for (e in S(listOf("c", "d"))) { println(e) }
    val g = G(listOf("x", "y"))
    val iter = g.iterator()
    while (iter.hasNext()) { println(iter.next()) }
}
