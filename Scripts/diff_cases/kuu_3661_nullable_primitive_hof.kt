// KUU-3661: map/forEach-family HOFs over List<Double?>/List<Long?>/List<ULong?>
// must preserve the null-vs-value distinction across the erased callback
// boundary. Unboxing an element whose box payload collides with the null
// sentinel (Long.MIN_VALUE, ULong 2^63, Double -0.0) must not turn it into
// null, and a real null element must not decode as the colliding value.
fun main() {
    println(listOf(1.5, null, -0.0).map { it.toString() })
    println(listOf(1L, null, Long.MIN_VALUE).map { it.toString() })
    println(listOf(1.5f, null, -0.0f).map { it.toString() })
    println(listOf(1uL, null, ULong.MAX_VALUE).map { it.toString() })
    println(listOf(1, null, 2).map { it.toString() })
    println(listOf("a", null, "b").map { it.toString() })

    listOf(1L, null, Long.MIN_VALUE).forEach { println(it.toString()) }
    listOf(1.5, null, -0.0).forEach { println(it.toString()) }

    println(listOf(1L, null, Long.MIN_VALUE).count { it != null })
    println(listOf(1.5, null, -0.0).count { it != null })
    println(listOf(1L, null, Long.MIN_VALUE).filter { it != null })
    println(listOf(1.5, null, -0.0).filter { it != null })

    // Adjacent boundaries the same sentinel boxes must survive: comparator
    // dispatch, fold accumulators, sequence transform results, filterNotNull.
    println(listOf<Long?>(1L, null, Long.MIN_VALUE).sortedWith(compareBy { it }))
    println(listOf<Double?>(1.5, null, -0.0).sortedWith(compareBy { it }))
    println(listOf(1L, null, Long.MIN_VALUE).fold(-1L as Long?) { acc, it -> (acc ?: 0L) + (it ?: 0L) })
    println(listOf(1.5, null, -0.0).fold(-1.5 as Double?) { acc, it -> (acc ?: 0.0) + (it ?: 0.0) })
    println(sequenceOf(1L, null, Long.MIN_VALUE).map { it }.toList())
    println(sequenceOf(1.5, null, -0.0).map { it }.toList())
    println(listOf<Long?>(1L, null, Long.MIN_VALUE).filterNotNull())
    println(listOf<Double?>(1.5, null, -0.0).filterNotNull())

    // Non-nullable element lists keep the same paths honest.
    println(listOf(1L, 2L, Long.MIN_VALUE).map { it + 1L })
    println(listOf(1.5, -0.0, 2.5).map { it * 2.0 })
    println(listOf(1uL, 2uL, ULong.MAX_VALUE).map { it.toString() })
}
