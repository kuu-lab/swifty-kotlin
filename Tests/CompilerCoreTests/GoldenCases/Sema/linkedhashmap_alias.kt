fun processLinkedMap(map: LinkedHashMap<String, Int>) {
    println(map.size)
}

fun createLinkedMap(): LinkedHashMap<Int, String> {
    return LinkedHashMap<Int, String>()
}

class OrderedMapHolder {
    val scores: LinkedHashMap<String, Int> = LinkedHashMap()
    val labels: LinkedHashMap<Int, String> = LinkedHashMap<Int, String>()
}

fun main() {
    val lhm: MutableMap<String, Int> = LinkedHashMap()
    lhm["z"] = 26
    lhm["a"] = 1
    lhm["m"] = 13
    println(lhm)
    println(lhm.keys.toList())
    println(lhm.values.toList())
    println(lhm.entries.map { "${it.key}=${it.value}" })
    lhm["z"] = 99
    println(lhm)
    lhm.remove("a")
    println(lhm.size)
    println(lhm.containsKey("m"))
    println(lhm.containsValue(99))

    val lhm2: LinkedHashMap<String, String> = LinkedHashMap()
    lhm2["key1"] = "value1"
    lhm2["key2"] = "value2"
    println(lhm2)

    // MutableMap operations through type alias
    val mutable: MutableMap<Int, String> = LinkedHashMap()
    mutable[1] = "one"
    mutable[2] = "two"
    mutable[3] = "three"
    println(mutable)

    // putAll operation
    mutable.putAll(mapOf(4 to "four", 5 to "five"))
    println(mutable)
    println(mutable.size)

    // get operations
    println(mutable[1])
    println(mutable[99])

    // Collection operations
    println(mutable.keys)
    println(mutable.values)
    println(mutable.entries)

    val generic: LinkedHashMap<Double, Boolean> = LinkedHashMap()
    generic[1.5] = true
    generic[2.7] = false
    println(generic)

    // Empty LinkedHashMap
    val empty: MutableMap<String, Int> = LinkedHashMap()
    println(empty.size)
    println(empty.isEmpty())

    // Iterator operations
    for ((key, value) in mutable) {
        println("$key=$value")
    }

    processLinkedMap(lhm2)

    val created = createLinkedMap()
    created[1] = "one"
    println(created.size)

    val holder = OrderedMapHolder()
    holder.scores["alice"] = 100
    println(holder.scores.size)
}
