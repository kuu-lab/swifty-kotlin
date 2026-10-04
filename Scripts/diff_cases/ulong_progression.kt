fun main() {
    // Basic ULongRange creation and contains
    val range = 1UL..10UL
    println(5UL in range)
    println(15UL in range)
    println(0UL in range)
    println(1UL in range)
    println(10UL in range)
    println(5UL !in range)

    // Empty range
    println((10UL..1UL).isEmpty())
    println((1UL..10UL).isEmpty())

    // ULongRange properties
    println((1UL..5UL).first)
    println((1UL..5UL).last)
    println((1UL..5UL).firstOrNull())
    println((1UL..5UL).lastOrNull())

    // ULongProgression with step
    println((1UL..10UL step 2).first)
    println((1UL..10UL step 2).last)
    println((1UL..10UL step 2).toList())
    println((1UL..10UL step 3).toList())
    println((1UL..10UL step 2L).toList())

    // downTo
    println((10UL downTo 1UL).toList())
    println((10UL downTo 1UL step 3).first)
    println((10UL downTo 1UL step 3).last)
    println((10UL downTo 1UL step 3).toList())
    println((10UL downTo 1UL step 3).count())

    // iterator / for loop
    for (i in 1UL..5UL) print("$i ")
    println()
    for (i in 1UL..10UL step 2) print("$i ")
    println()
    for (i in 10UL downTo 1UL step 3) print("$i ")
    println()
    val iterator = (1UL..3UL).iterator()
    while (iterator.hasNext()) print("${iterator.next()};")
    println()

    // rangeTo as an explicit call
    println(1UL.rangeTo(5UL))
    println(1UL..5UL)
    println(1UL..10UL step 2)

    // take / drop / chunked / windowed on ULongRange
    println((1UL..5UL).take(3))
    println((1UL..5UL).drop(2))
    println((1UL..5UL).take(0))
    println((1UL..5UL).drop(20))
    println((1UL..5UL).chunked(2))
    println((1UL..5UL).windowed(3))
    println((1UL..5UL).windowed(3, 2, true))

    // take / drop / chunked / windowed on ULongProgression
    val progression = 1UL..9UL step 2
    println(progression.take(2))
    println(progression.drop(1))
    println(progression.chunked(2))
    println(progression.windowed(2))
    println((5UL downTo 1UL).windowed(2, 2, true))

    try {
        (1UL..5UL).take(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        (1UL..5UL).drop(-1)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        (1UL..5UL).chunked(0)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        (1UL..5UL).windowed(2, 0, false)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        (1UL..10UL step 0).toList()
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    // forEach and map
    (1UL..5UL).forEach { print("$it ") }
    println()
    println((1UL..5UL).map { it * 2UL })

    // sum and count
    println((1UL..5UL).sum())
    println((1UL..5UL).count())

    // until (exclusive end)
    println((1UL..<5UL).toList())

    // ULong.MAX_VALUE non-regression: step alignment must use unsigned math,
    // not a signed modulo that would corrupt the aligned last for very wide
    // ranges (distance exceeding Long.MAX_VALUE).
    println((0UL..ULong.MAX_VALUE step 3).last)
    println((ULong.MAX_VALUE downTo 0UL step 7).last)
    println((ULong.MAX_VALUE - 2UL..ULong.MAX_VALUE).toList())
    println((ULong.MAX_VALUE - 6UL..ULong.MAX_VALUE step 3).toList())
}
