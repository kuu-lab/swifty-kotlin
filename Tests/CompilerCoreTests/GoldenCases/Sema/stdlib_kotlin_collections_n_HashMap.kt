fun acceptsHashMap(map: HashMap<String, Int>): MutableMap<String, Int> = map

fun main() {
    val map: HashMap<String, Int> = HashMap()
    map["a"] = 1
    val mutable: MutableMap<String, Int> = map
    mutable["b"] = 2

    val withCapacity = HashMap<String, Int>(8)
    val withLoadFactor = HashMap<String, Int>(8, 0.75f)
    val copy = HashMap(map)
    println(acceptsHashMap(copy).size)
    println(withCapacity.size)
    println(withLoadFactor.size)
}
