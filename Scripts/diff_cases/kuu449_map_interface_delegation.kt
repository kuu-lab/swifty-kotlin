// KUU-449: Map interface delegation must resolve and preserve the delegate.

class CustomMap : Map<String, Int> by mapOf("k" to 1)

fun readMap(map: Map<String, Int>) {
    println(map.isEmpty())
    println(map.containsKey("k"))
    println(map["k"])
    println(map.keys.size)
}

fun main() {
    val m = CustomMap()
    readMap(m)
    println(m.isEmpty())
    println(m.containsKey("k"))
    println(m["k"])
    println(m.keys.size)
}
