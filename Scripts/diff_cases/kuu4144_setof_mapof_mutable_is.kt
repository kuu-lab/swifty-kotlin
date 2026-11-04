// KUU-4144: read-only setOf/mapOf factory results carry JVM implementation
// identity — 2+ elements are LinkedHashSet/LinkedHashMap under the read-only
// Set/Map type, so `is MutableSet`/`is MutableMap` and mutable casts succeed;
// singletons are Collections$Singleton* (erased-mutable but UOE on write);
// empty factories are the shared EmptySet/EmptyMap (not mutable at all).
// Emptying a formerly multi-element collection keeps its impl class.

fun main() {
    // Multi-element read-only factories: mutable under the read-only type.
    println(setOf(1, 2) is MutableSet<*>)
    println(setOf(1, 2) is LinkedHashSet<*>)
    println(setOf(1, 2) is HashSet<*>)
    println(mapOf(1 to 2, 3 to 4) is MutableMap<*, *>)
    println(mapOf(1 to 2, 3 to 4) is LinkedHashMap<*, *>)
    println(mapOf(1 to 2, 3 to 4) is HashMap<*, *>)

    // Mutable casts mutate, matching LinkedHashSet/LinkedHashMap on the JVM.
    val castSet = setOf(1, 2) as MutableSet<Int>
    castSet.add(3)
    println(castSet)
    val castMap = mapOf(1 to 2, 3 to 4) as MutableMap<Int, Int>
    castMap[5] = 6
    println(castMap)

    // Singletons: erased `java.util.Set`/`Map` impls answer mutable checks
    // true, but are not LinkedHash* and reject mutation.
    println(setOf(1) is MutableSet<*>)
    println(setOf(1) is LinkedHashSet<*>)
    println(mapOf(1 to 2) is MutableMap<*, *>)
    println(mapOf(1 to 2) is LinkedHashMap<*, *>)
    try {
        (setOf(1) as MutableSet<Int>).add(2)
        println("unexpected")
    } catch (e: UnsupportedOperationException) {
        println("singleton add UOE")
    }

    // Empty factories: canonical EmptySet/EmptyMap, never mutable.
    println(setOf<Int>() is MutableSet<*>)
    println(mapOf<Int, Int>() is MutableMap<*, *>)
    try {
        setOf<Int>() as MutableSet<Int>
        println("unexpected")
    } catch (e: ClassCastException) {
        println("empty cast CCE")
    }

    // Mutable map views carry mutable view identity; emptyMap's views share
    // the canonical EmptySet/EmptyList.
    println(mutableMapOf(1 to 2).keys is MutableSet<*>)
    println(mutableMapOf(1 to 2).entries is MutableSet<*>)
    println(mutableMapOf(1 to 2).values is MutableCollection<*>)
    println(mutableMapOf(1 to 2).values is List<*>)
    println(emptyMap<Int, Int>().keys is MutableSet<*>)
    println(emptyMap<Int, Int>().values is List<*>)
    println(emptyMap<Int, Int>().values is MutableList<*>)

    // JDK SingletonMap.values is a Collections$SingletonSet — a Set impl.
    println(mapOf(1 to 2).values is Set<*>)
    println(mapOf(1 to 2).values is MutableSet<*>)
    println(mapOf(1 to 2).values is List<*>)
    println(mapOf(1 to 2).values::class.simpleName)
    println(mapOf(1 to 2).keys::class.simpleName)

    // setOfNotNull: single-element overload is EmptySet/singleton; the vararg
    // overload is a mutable LinkedHashSet for any supplied count.
    println(setOfNotNull(null) is MutableSet<*>)
    println(setOfNotNull(1) is MutableSet<*>)
    println(setOfNotNull(1) is LinkedHashSet<*>)
    println(setOfNotNull(1, 2) is MutableSet<*>)
    println(setOfNotNull(1, 2) is LinkedHashSet<*>)

    // Reflection before and after emptying keeps the impl class.
    println(setOf<Int>()::class.simpleName)
    println(setOf(1)::class.simpleName)
    println(setOf(1, 2)::class.simpleName)
    println(mapOf<Int, Int>()::class.simpleName)
    println(mapOf(1 to 2)::class.simpleName)
    println(mapOf(1 to 2, 3 to 4)::class.simpleName)
    val drained = mutableSetOf(1, 2)
    drained.remove(1)
    drained.remove(2)
    println(drained::class.simpleName)
    val drainedMap = mutableMapOf(1 to 2)
    drainedMap.remove(1)
    println(drainedMap::class.simpleName)
}
