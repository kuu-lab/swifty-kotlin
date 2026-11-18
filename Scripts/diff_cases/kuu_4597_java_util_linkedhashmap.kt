// KUU-4597: java.util.LinkedHashMap must resolve like kotlinc-jvm, while the
// runtime remains the existing kotlin.collections.LinkedHashMap implementation.
import java.util.LinkedHashMap

fun main() {
    val imported = LinkedHashMap<String, Int>()
    imported["b"] = 2
    imported["a"] = 1
    println(imported)
    println(imported.keys.toList())

    val qualified: java.util.LinkedHashMap<String, Int> = java.util.LinkedHashMap()
    qualified["x"] = 24
    println(qualified)
}
