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

    // contains on stepped progressions. NOTE: real kotlinc linear-scans `in`
    // on progressions, so spans are kept small enough to verify — the
    // full-span (>2^63 distance) variants are covered by unit tests and by
    // the ULong cases below.
    println(Int.MAX_VALUE in (Int.MIN_VALUE + 2..Int.MAX_VALUE))
    println(1 in (10 downTo 1 step 3))
    println(0 in (10 downTo 1 step 3))
    println(7 in (1..10 step 3))

    // take/drop/sum on boundary-ending IntRanges.
    println((Int.MAX_VALUE - 1..Int.MAX_VALUE).take(5))
    println((Int.MAX_VALUE - 1..Int.MAX_VALUE).drop(1))
    println((Int.MIN_VALUE..Int.MIN_VALUE).sum())

    // Int sums wrap at 32 bits (Int.MIN + (MIN+1) + (MIN+2) mod 2^32).
    println((Int.MIN_VALUE..Int.MIN_VALUE + 2).sum())

    // Descending ULong contains: the Kotlin-side path keeps ULong
    // comparisons exact; negative step must not sign-extend.
    println((9uL downTo 0uL step 3).contains(0uL))
    println((9uL downTo 0uL step 3).contains(4uL))
    println((9uL downTo 3uL step 3).contains(0uL))
}
