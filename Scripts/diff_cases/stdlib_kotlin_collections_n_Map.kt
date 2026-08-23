// KSP-941: source-backed Map shell and read-only query semantics.
abstract class CustomMap : Map<String, Int>

fun main() {
    val values: Map<String, Int?> = mapOf(
        "present" to 7,
        "nullable" to null
    )

    println(values["present"] ?: -1)
    println(values["nullable"] ?: -2)
    println(values["missing"] ?: -3)
    println(values.containsKey("nullable"))
    println(values.containsKey("missing"))
    println(values.containsValue(null))
    println(values.keys.sorted())
    println(values.values.toList().map { it ?: -4 }.sorted())
    println(values.entries.map { "${it.key}:${it.value ?: -5}" }.sorted())
    println(if (values is Map<*, *>) "map" else "other")

    val widened: Map<String, Number?> = values
    println(widened["present"] ?: -6)
}
