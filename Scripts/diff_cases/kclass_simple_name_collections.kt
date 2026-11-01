// KUU-3963: bound `::class` on stdlib-produced collections reflects the JVM
// implementation class names (java.util.Collections.SingletonList, anonymous
// iterators, ...), matching kotlinc.
fun n(k: kotlin.reflect.KClass<*>): String = "${k.simpleName}|${k.qualifiedName}"

fun main() {
    println(n(listOf(1)::class))
    println(n(listOf(1, 2)::class))
    println(n(emptyList<Int>()::class))
    println(n(setOf(1)::class))
    println(n(setOf(1, 2)::class))
    println(n(emptySet<Int>()::class))
    println(n(mapOf(1 to "a")::class))
    println(n(mapOf(1 to "a", 2 to "b")::class))
    println(n(emptyMap<Int, Int>()::class))
    println(n(mapOf(1 to "a", 2 to "b").keys::class))
    println(n(mapOf(1 to "a", 2 to "b").values::class))
    println(n(mapOf(1 to "a", 2 to "b").entries::class))
    println(n(mapOf(1 to "a").keys::class))
    println(n(emptyMap<Int, Int>().entries::class))
    println(n(mapOf(1 to "a", 2 to "b").entries.first()::class))
    println(n(listOf(1, 2).subList(0, 1)::class))
    println(n(arrayListOf(1, 2).subList(0, 1)::class))
    println(n(listOf(1, 2).asReversed()::class))
    println(n(arrayOf(1, 2).asList()::class))
    println(n(intArrayOf(1, 2).asList()::class))
    println(n(sortedSetOf(1, 2)::class))
    println(n(sortedMapOf(1 to "a", 2 to "b")::class))
    println(n(sortedMapOf(1 to "a", 2 to "b").keys::class))
    println(n(sortedMapOf(1 to "a", 2 to "b").values::class))
    println(n(sortedMapOf(1 to "a", 2 to "b").entries::class))
    println(n(hashMapOf(1 to "a", 2 to "b").keys::class))
    println(n(hashMapOf(1 to "a", 2 to "b").values::class))
    println(n(hashMapOf(1 to "a", 2 to "b").entries::class))
    println(n(hashMapOf(1 to "a", 2 to "b").entries.first()::class))
    println(n(mapOf(1 to "a", 2 to "b").entries.first()::class))
    println(n(mapOf(1 to "a").entries.first()::class))
    println(n(sortedMapOf(1 to "a", 2 to "b").entries.first()::class))
    println(n(buildList { add(1); add(2) }::class))
    println(n(buildSet { add(1); add(2) }::class))
    println(n(buildMap { put(1, "a"); put(2, "b") }::class))
    println(n(ArrayDeque(listOf(1, 2))::class))
    println(n(Pair(1, 2)::class))
    // Anonymous object literals report null names like the JVM.
    val obj = object { val x = 1 }
    println(n(obj::class))
    val iter = object : Iterator<Int> {
        override fun hasNext() = false
        override fun next() = 0
    }
    println(n(iter::class))
}
