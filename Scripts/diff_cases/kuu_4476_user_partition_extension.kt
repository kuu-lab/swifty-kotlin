fun <V, E> Iterable<Pair<V, E>>.partition(): Pair<List<V>, List<E>> =
    Pair(map { it.first }, map { it.second })

fun main() {
    val p = listOf(1 to "x", 2 to "y").partition()
    println(p.first)
    println(p.second)
    val (a, b) = listOf(3 to "z").partition()
    println(a)
    println(b)
    // The bundled partition(predicate) must keep winning for the 1-arg shape.
    println(listOf(1, 2, 3, 4).partition { it % 2 == 0 }.first)
}
