fun main() {
    val emptyMap = hashMapOf<String?, String?>()
    emptyMap[null] = null
    println(emptyMap.size)
    println(emptyMap.containsKey(null))

    val map = hashMapOf("a" to 1, "a" to 2, "b" to 3)
    println(map.size)
    println(map["a"])
    println(map["b"])

    val pairs = arrayOf("c" to 4, "d" to 5)
    val spreadMap = hashMapOf<String, Int>(*pairs)
    println(spreadMap.size)
    println(spreadMap["d"])

    val emptySet = hashSetOf<String?>()
    emptySet.add(null)
    emptySet.add(null)
    println(emptySet.size)

    val set = hashSetOf(1, 2, 2)
    println(set.size)
    println(set.contains(2))

    val elements = arrayOf(3, 4, 4)
    val spreadSet = hashSetOf<Int>(*elements)
    println(spreadSet.size)
    println(emptyMap !== hashMapOf<String?, String?>())
    println(emptySet !== hashSetOf<String?>())
}
