fun main() {
    // KUU-819: signed range iteration must terminate at the inclusive
    // endpoint instead of wrapping to the opposite boundary.

    // Singleton ranges on the boundary.
    println((Long.MAX_VALUE..Long.MAX_VALUE).toList())
    println((Long.MIN_VALUE..Long.MIN_VALUE).toList())
    println((Long.MAX_VALUE..Long.MAX_VALUE).count())

    // Multi-element progressions ending exactly on the boundary.
    println((Long.MAX_VALUE - 4L..Long.MAX_VALUE step 2L).toList())
    println((Long.MIN_VALUE + 4L downTo Long.MIN_VALUE step 2L).toList())

    // reversed() of a boundary-ending range.
    println((Long.MAX_VALUE - 2L..Long.MAX_VALUE).reversed().toList())

    // Explicit iterator stays exhausted after the endpoint.
    val it = (Long.MAX_VALUE - 1L..Long.MAX_VALUE).iterator()
    while (it.hasNext()) println(it.next())
    println(it.hasNext())

    // for-in over a boundary-ending range.
    for (v in Long.MAX_VALUE - 2L..Long.MAX_VALUE) println(v)

    // contains on full-span stepped progressions (distance overflows Int64).
    // NOTE: descending `in` is intentionally omitted — reference kotlinc
    // falls back to a linear scan for downTo progressions and times out.
    println(Int.MAX_VALUE in (Int.MIN_VALUE..Int.MAX_VALUE step 3))
    println(Int.MAX_VALUE in (Int.MIN_VALUE..Int.MAX_VALUE step 2))

    // take/drop/sum on boundary-ending IntRanges.
    println((Int.MAX_VALUE - 1..Int.MAX_VALUE).take(5))
    println((Int.MAX_VALUE - 1..Int.MAX_VALUE).drop(1))
    println((Int.MIN_VALUE..Int.MIN_VALUE).sum())
}
