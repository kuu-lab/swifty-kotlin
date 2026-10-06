// KUU-1420: `for (e in map)` elements are real Map.Entry objects. On
// MutableMap the element is MutableEntry and setValue writes through; on
// read-only Map the element supports key/value reads. Destructuring keeps
// yielding key/value pairs.
fun main() {
    val mutable = mutableMapOf("a" to 1, "b" to 2)
    for (e in mutable) {
        e.setValue(e.value + 10)
    }
    println(mutable)
    for (e in mutable) {
        println("${e.key}:${e.value}")
    }

    val readOnly: Map<String, Int> = mapOf("x" to 7, "y" to 8)
    for (e in readOnly) {
        println("${e.key}=${e.value}")
    }

    for ((k, v) in mutable) {
        println("$k->$v")
    }
    for ((k, v) in readOnly) {
        println("$k,$v")
    }
}
