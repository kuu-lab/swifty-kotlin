// KUU-1944: LinkedHashMap permits user subclasses and preserves insertion order.
class OrderedMap : LinkedHashMap<String, Int>()

fun main() {
    val ordered = OrderedMap()
    ordered["b"] = 2
    ordered["a"] = 1
    println(ordered.keys.joinToString(","))
    println(ordered.values.joinToString(","))
}
