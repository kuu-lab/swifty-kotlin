fun main() {
    val map = HashMap<String, Int>()
    map["a"] = 1
    map["b"] = 2
    val typed: HashMap<String, Int> = HashMap<String, Int>()
    typed["typed"] = 4

    val mutable: MutableMap<String, Int> = map
    mutable["c"] = 3
    println(map["a"])
    println(map.remove("b"))
    println(map["missing"])
    println(map.size)
    println(map.entries.toList().joinToString(",") { "${it.key}=${it.value}" })

    val copy = HashMap(map)
    println(copy == map)
    println(map == copy)
    println(map is HashMap<*, *>)
    println(map is MutableMap<*, *>)

    val withCapacity = HashMap<String, Int>(8)
    val withLoadFactor = HashMap<String, Int>(8, 0.75f)
    withCapacity["capacity"] = 8
    withLoadFactor["load"] = 75
    println(withCapacity.size + withLoadFactor.size + typed.size)
}
