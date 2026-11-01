// KUU-4019: java.util.Map replace-family members on bundled MutableMap.
fun main() {
    val map = mutableMapOf("a" to 1)
    println(map.replace("a", 10))
    println(map.replace("missing", 99))
    println(map.replace("a", 10, 42))
    println(map.replace("a", 999, 77))
    println(map)

    val hash: HashMap<String, Int> = hashMapOf("x" to 1)
    println(hash.replace("x", 2))
    val linked: LinkedHashMap<String, Int> = linkedMapOf("y" to 3)
    println(linked.replace("y", 4))

    val all = mutableMapOf("a" to 1, "b" to 2)
    all.replaceAll { _, value -> value * 10 }
    println(all)

    val nullable = mutableMapOf<String, Int?>("null" to null, "old" to 1)
    println(nullable.replace("null", 5))
    println(nullable.replace("absent", 7))
    println(nullable.containsKey("absent"))
    println(nullable.replace("null", 5, 8))
    println(nullable.replace("absent", null, 9))
    println(nullable)
}
