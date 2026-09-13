// RF-LOWER-CALL-012: contracts of the Map-exclusive HOFs that map_hof.kt and
// map_entries_hof.kt leave uncovered — colliding keys from a non-injective
// mapKeys transform, the insertion order of the resulting map, and a lambda
// that throws part-way through the traversal.
fun main() {
    val m = mapOf("a" to 1, "bb" to 2, "ccc" to 3)

    // Non-injective mapKeys: later entries overwrite earlier ones, and the
    // surviving entry keeps the position of the first occurrence of the key.
    println(m.mapKeys { it.key.length % 2 })
    println(m.mapKeys { "same" })
    println(m.mapKeys { it.key.length % 2 }.size)

    // Insertion order follows the receiver's iteration order, not key order.
    val reordered = mapOf("z" to 1, "a" to 2, "m" to 3)
    println(reordered.mapValues { it.value * 2 })
    println(reordered.mapKeys { it.key.uppercase() })
    println(reordered.filterKeys { it != "a" })
    println(reordered.filterValues { it != 2 })
    println(reordered.mapValues { it.value }.keys.toList())

    // mapKeysTo with colliding keys writes into the destination in traversal
    // order, so the destination keeps its own pre-existing entries first.
    val keyDestination = mutableMapOf("seed" to 9)
    println(m.mapKeysTo(keyDestination) { (it.key.length % 2).toString() }.size)
    println(keyDestination)

    val valueDestination = mutableMapOf("a" to "seed")
    println(m.mapValuesTo(valueDestination) { it.value.toString() })
    println(valueDestination["a"])

    // A throwing transform propagates and leaves no partial result bound.
    try {
        m.mapValues { if (it.value == 2) throw IllegalStateException("boom") else it.value }
        println("not reached")
    } catch (e: IllegalStateException) {
        println("mapValues threw ${e.message}")
    }
    try {
        m.mapKeys { if (it.key == "bb") throw IllegalStateException("keys") else it.key }
        println("not reached")
    } catch (e: IllegalStateException) {
        println("mapKeys threw ${e.message}")
    }
    try {
        m.filterKeys { if (it == "ccc") throw IllegalStateException("filter") else true }
        println("not reached")
    } catch (e: IllegalStateException) {
        println("filterKeys threw ${e.message}")
    }
    try {
        m.filterValues { if (it == 3) throw IllegalStateException("values") else true }
        println("not reached")
    } catch (e: IllegalStateException) {
        println("filterValues threw ${e.message}")
    }
}
