// KSP-431: Map lookup/conversion APIs backed by bundled Kotlin source.
fun main() {
    val map = mapOf("a" to 1, "b" to 2, "c" to 3)

    println(map.getValue("b"))
    println(map.getOrDefault("z", -1))
    println(map.getOrDefault("a", -1))
    println(map.getOrElse("z") { 42 })
    println(map.getOrElse("c") { 42 })
    println(map.containsKey("a"))
    println(map.containsKey("z"))
    println(map.containsValue(3))
    println(map.containsValue(99))
    println(map.keys)
    println(map.values)
    println(map.entries)
    println(map.toList())

    val mutable = map.toMutableMap()
    mutable["d"] = 4
    println(mutable.size)
    println(mutable.getOrPut("d") { 40 })
    println(mutable.getOrPut("e") { 5 })
    println(mutable["e"])

    val missing: Map<String, Int>? = null
    println(missing.orEmpty())
    println(missing.orEmpty().size)
    println(map.orEmpty().size)

    val defaulted = map.withDefault { key -> key.length }
    println(defaulted.getValue("a"))
    println(defaulted.getValue("zzzz"))

    try {
        map.getValue("nope")
    } catch (e: NoSuchElementException) {
        println("caught")
    }

    for (entry in map.entries) {
        println("${entry.key}=${entry.value}")
    }

    val nullable: Map<String, Int?> = mapOf("a" to null, "b" to 2)
    println(nullable.getValue("a"))
    println(nullable.getOrDefault("a", 7))
    println(nullable.getOrDefault("z", 7))
    println(nullable.getOrElse("a") { 9 })
    println(nullable.containsKey("a"))
    println(nullable.containsValue(null))
    println(nullable.keys)
    println(nullable.values)
    println(nullable.toList())

    val nullableMutable = nullable.toMutableMap()
    println(nullableMutable.getOrPut("a") { 5 })
    println(nullableMutable)

    val pairs: List<Pair<String, Int>> = map.toList()
    println(pairs.first().first)
    println(pairs.first().second)
    val keySet: Set<String> = map.keys
    val valueCollection: Collection<Int> = map.values
    val entrySet: Set<Map.Entry<String, Int>> = map.entries
    println(keySet.size + valueCollection.size + entrySet.size)
    for ((key, value) in map.toList()) {
        println("$key -> $value")
    }
}
