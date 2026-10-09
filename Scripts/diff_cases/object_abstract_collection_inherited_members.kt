// KUU-1251: inherited methods must dispatch to anonymous-class property overrides.
fun main() {
    val list = object : AbstractList<Int>() {
        override val size = 2
        override fun get(index: Int) = index * 10
    }
    println(list.size)
    println(list[1])
    println(list)
    println(list.indexOf(10))
    println(list.lastIndexOf(0))
    println(list.subList(1, 2))
    val baseList: AbstractList<Int> = list
    println(baseList.size)
    println(baseList.indexOf(10))
    val erasedList: Any = list
    println(erasedList)

    val collection = object : AbstractCollection<Int>() {
        override val size: Int get() = 2
        override fun iterator(): Iterator<Int> = listOf(3, 4).iterator()
    }
    println(collection)
    println(collection.contains(4))
    println(collection.isEmpty())

    val set = object : AbstractSet<Int>() {
        override val size = 2
        override fun iterator(): Iterator<Int> = listOf(5, 6).iterator()
    }
    println(set)
    println(set.contains(6))
    val baseSet: AbstractSet<Int> = set
    println(baseSet.size)

    val map = object : AbstractMap<String, Int>() {
        override val entries: Set<Map.Entry<String, Int>>
            get() = mapOf("a" to 7, "b" to 8).entries
    }
    println(map)
    println(map.size)
    println(map["b"])
    println(map.containsKey("a"))
    val baseMap: AbstractMap<String, Int> = map
    println(baseMap.entries.size)
    val erasedMap: Any = map
    println(erasedMap)
}
