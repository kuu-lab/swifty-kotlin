fun named(vararg n: Pair<String, Int>) = n.toMap()

fun <K, V> copyPairs(source: Array<out Pair<K, V>>): Map<K, V> = source.toMap()

fun <K, V, M : MutableMap<in K, in V>> copyPairsInto(
    source: Array<out Pair<K, V>>,
    destination: M,
): M = source.toMap(destination)

fun main() {
    println(named("a" to 1))
    println(named("a" to 1, "b" to 2))
    println(named())

    val arr: Array<Pair<String, Int>> = arrayOf("x" to 3, "y" to 4)
    println(arr.toMap())
    val out: Array<out Pair<String, Int>> = arr
    println(out.toMap())
    println(arrayOf("z" to 5).toMap())

    println(mapOf("k" to 9).toMap())
    println(listOf("l" to 8).toMap())

    println(arrayOf("a" to 1, "a" to 2).toMap())
    println(copyPairs(arr))
    println(emptyArray<Pair<String, Int>>().toMap())

    val destination = mutableMapOf<String, Int>("seed" to -1)
    println(arr.toMap(destination) === destination)
    println(destination)
    println(copyPairsInto(out, mutableMapOf()))
}
