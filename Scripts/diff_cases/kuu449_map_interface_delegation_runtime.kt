// KUU-449: Map delegation must preserve a non-empty map through a Map parameter.

class CustomMap : Map<String, Int> by mapOf("k" to 1)

fun readMap(map: Map<String, Int>) {
    println(map.isEmpty())
    println(map.containsKey("k"))
    println(map["k"])
    println(map.keys.size)
}

fun main() {
    readMap(CustomMap())
}
