// KUU-4040: java.util.Map.compute on bundled MutableMap types — the
// remapping function always runs with the current value or null, a null
// result removes the mapping, and a non-null result is stored and returned.
import java.util.HashMap

fun main() {
    val map = HashMap<String, Int>()
    map["a"] = 1
    println(map.compute("a") { _, v -> (v ?: 0) + 10 })
    println(map.compute("missing") { _, v -> if (v == null) 7 else -1 })
    println(map.compute("a") { _, _ -> null })
    println(map.containsKey("a"))
    println(map.compute("missing") { _, _ -> null })
    println(map.size)
    println(map)

    val values = mutableMapOf<String, Int?>("nullVal" to null, "present" to 2)
    println(values.compute("nullVal") { _, v -> if (v == null) 99 else -1 })
    println(values.compute("present") { _, v -> v?.times(3) })
    println(values.compute("absent") { _, v -> if (v == null) 42 else -1 })
    println(values.compute("absent") { _, _ -> null })
    println(values.containsKey("absent"))
    println(values)

    // replaceAll parity (KUU-4019): java.util.HashMap keeps null-valued
    // entries rather than removing them. Iteration order differs between
    // implementations, so only order-insensitive observations are printed.
    val all = HashMap<String, Int?>()
    all["x"] = 1
    all["y"] = 2
    all.replaceAll { _, _ -> null }
    println(all.size)
    println(all.containsKey("x"))
    println(all.containsKey("y"))
    println(all["x"])
    println(all["y"])
}
