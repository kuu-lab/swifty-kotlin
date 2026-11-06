// KUU-4346: Map.plus/Map.minus receivers must be `Map<out K, V>` like upstream
// so that calls whose key argument widens K beyond the receiver's key type are
// accepted (previously rejected with conflicting type-variable bounds).

fun probe(m: Map<String, Int?>) {
    val byKey = m - 1.5
    val byIterable = m - listOf("x", 1)
    val byPair = m + (1 to "x")
    val wideKey: Map<Any, Int?> = m - 1.5
    val wideIterable: Map<Any, Int?> = m - listOf("x", 1)
    val same: Map<String, Int?> = m - "a"
    println("$byKey|$byIterable|$byPair|$wideKey|$wideIterable|$same")
}

fun main() {
    probe(mapOf("a" to 1, "b" to null))
    val map = mapOf("a" to 1, "b" to 2)
    println(map.minus("x"))
    println(map.minus(1.5))
    println(map.minus(listOf("x")))
    println(map.minus(arrayOf("x")))
    println(map.minus(sequenceOf("x")))
}
