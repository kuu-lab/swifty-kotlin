fun main() {
    // Basic toMutableMap: creates independent mutable copy
    val original = mapOf("a" to 1, "b" to 2, "c" to 3)
    val mutable = original.toMutableMap()
    println(mutable)
    println(mutable.size)

    // Mutation does not affect original
    mutable["d"] = 4
    mutable["a"] = 99
    println(original)
    println(mutable)

    // toMutableMap on empty map
    val emptyMap = emptyMap<String, Int>()
    val emptyMutable = emptyMap.toMutableMap()
    println(emptyMutable)
    println(emptyMutable.isEmpty())
    emptyMutable["x"] = 10
    println(emptyMutable)

    // toMutableMap on mutableMapOf result (creates a copy)
    val m1 = mutableMapOf("k1" to "v1")
    val m2 = m1.toMutableMap()
    m2["k2"] = "v2"
    println(m1)
    println(m2)

    // toMutableMap preserves last value for duplicate keys in source
    val withDups = mapOf("a" to 1, "b" to 2, "a" to 3)
    val dupMutable = withDups.toMutableMap()
    println(dupMutable)

    // toMutableMap with remove operations
    val src = mapOf(1 to "one", 2 to "two", 3 to "three")
    val copy = src.toMutableMap()
    copy.remove(2)
    println(src)
    println(copy)

    // toMutableMap with nullable values
    val nullableMap = mapOf("a" to null, "b" to 2, "c" to null)
    val nullableMutable = nullableMap.toMutableMap()
    nullableMutable["a"] = 42
    nullableMutable["d"] = null
    println(nullableMutable)

    // toMutableMap on result of filter
    val filtered = mapOf(1 to 10, 2 to 20, 3 to 30).filter { it.value > 15 }
    val filteredMutable = filtered.toMutableMap()
    filteredMutable[4] = 40
    println(filteredMutable)

    // Chained operations: mapValues then toMutableMap
    val mapped = mapOf("x" to 1, "y" to 2).mapValues { it.value * 10 }.toMutableMap()
    mapped["z"] = 30
    println(mapped)

    // containsKey / containsValue on mutable copy
    val check = mapOf("hello" to 1, "world" to 2).toMutableMap()
    println(check.containsKey("hello"))
    println(check.containsValue(2))
    println(check.containsKey("missing"))

    // Iteration over toMutableMap result
    val iterMap = mapOf(1 to "a", 2 to "b").toMutableMap()
    for ((k, v) in iterMap) {
        println("$k=$v")
    }

    // keys, values, entries
    val kvMap = mapOf("p" to 1, "q" to 2).toMutableMap()
    println(kvMap.keys.sorted())
    println(kvMap.values.sorted())
}
