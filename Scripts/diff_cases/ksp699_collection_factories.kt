// KSP-699: every kotlin.collections factory function is a source-backed
// declaration (CollectionFactories.kt / hash.kt / linked.kt) with no bootstrap
// synthetic stub. `arrayListOf` was the last stub, so this case pins its
// nominal identity, mutability and element typing alongside the other
// factories.
//
// `mutableSetOf(...) is MutableSet<*>` and `linkedSetOf(...) is LinkedHashSet<*>`
// are intentionally absent: they still answer false because `__kk_set_of` tags
// its box as the read-only `Set`, and no mutable/linked-tagged set bridge
// exists yet. Tracked as BUG-254.

fun main() {
    // arrayListOf: nominal identity + mutability + element typing
    val empty = arrayListOf<Int>()
    println(empty)
    println(empty.size)
    println(empty is ArrayList<*>)
    println(empty is MutableList<*>)
    empty.add(1)
    empty.add(2)
    println(empty)

    val filled = arrayListOf(10, 20, 30)
    println(filled)
    println(filled.size)
    println(filled[1])
    filled.add(40)
    filled.removeAt(0)
    println(filled)
    println(filled is ArrayList<*>)
    println(filled is MutableList<*>)
    println(filled is List<*>)

    val declared: ArrayList<String> = arrayListOf("a", "b")
    declared.add("c")
    println(declared.joinToString("-"))

    // mutableListOf declares a mutable result, so it carries the same tag
    println(mutableListOf(1) is ArrayList<*>)
    println(mutableListOf(1) is MutableList<*>)
    println(mutableListOf(1) is List<*>)
    println(listOf(1) is List<*>)

    // Remaining factories: nominal identity where the runtime tag is exact
    println(hashSetOf(1) is HashSet<*>)
    println(hashSetOf(1) is MutableSet<*>)
    println(setOf(1) is Set<*>)
    println(mutableMapOf("a" to 1) is MutableMap<*, *>)
    println(mapOf("a" to 1) is Map<*, *>)

    // Contents of the set/map factories whose `is` checks BUG-254 covers
    println(mutableSetOf(1, 2, 2).size)
    val ms = mutableSetOf(1, 2)
    ms.add(3)
    println(ms)
    println(linkedSetOf(3, 1, 3, 2))
    println(hashMapOf("a" to 1, "b" to 2)["b"])
    println(linkedMapOf("b" to 2, "a" to 1).keys.joinToString(","))

    // listOfNotNull / setOfNotNull keep filtering nulls
    println(listOfNotNull(1, null, 3))
    println(listOfNotNull<Int>(null))
    println(setOfNotNull(1, null, 1))

    // Empty factories
    println(emptyList<Int>())
    println(emptySet<Int>())
    println(emptyMap<String, Int>())
    println(listOf<Int>())
    println(setOf<Int>())
    println(mapOf<String, Int>())
}
