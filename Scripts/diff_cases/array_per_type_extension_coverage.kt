// KUU-2781: array extensions must exist for every receiver array type, not only some of them.
fun main(args: Array<String>) {
    // isNotEmpty on Array<T> and every primitive array
    println(args.isNotEmpty())
    println(arrayOf(1, 2).isNotEmpty())
    println(booleanArrayOf(true).isNotEmpty())
    println(byteArrayOf().isNotEmpty())
    println(shortArrayOf(1).isNotEmpty())
    println(charArrayOf('a').isNotEmpty())
    println(intArrayOf().isNotEmpty())
    println(longArrayOf(1L).isNotEmpty())
    println(floatArrayOf(1f).isNotEmpty())
    println(doubleArrayOf().isNotEmpty())

    // distinct
    println(booleanArrayOf(true, false, true).distinct())
    println(byteArrayOf(1, 2, 1).distinct())
    println(shortArrayOf(1, 2, 1).distinct())
    println(charArrayOf('a', 'b', 'a').distinct())
    println(intArrayOf(1, 2, 1).distinct())
    println(longArrayOf(1L, 2L, 1L).distinct())
    println(floatArrayOf(1f, 2f, 1f).distinct())
    println(doubleArrayOf(1.0, 2.0, 1.0).distinct())

    // withIndex
    println(booleanArrayOf(true, false).withIndex().map { "${it.index}:${it.value}" })
    println(charArrayOf('a', 'b').withIndex().map { "${it.index}:${it.value}" })
    println(floatArrayOf(1.5f, 2.5f).withIndex().map { "${it.index}:${it.value}" })
    println(doubleArrayOf(1.0).withIndex().map { it.index })

    // sorted
    println(byteArrayOf(3, 1, 2).sorted())
    println(shortArrayOf(3, 1, 2).sorted())
    println(charArrayOf('c', 'a', 'b').sorted())
    println(intArrayOf(3, 1, 2).sorted())
    println(longArrayOf(3L, 1L, 2L).sorted())
    println(floatArrayOf(3f, 1f, 2f).sorted())
    println(doubleArrayOf(3.0, 1.0, 2.0).sorted())

    // sumOf
    println(booleanArrayOf(true, false, true).sumOf { if (it) 1 else 0 })
    println(byteArrayOf(1, 2).sumOf { it.toInt() })
    println(shortArrayOf(1, 2).sumOf { it.toLong() })
    println(intArrayOf(1, 2, 3).sumOf { it * 2 })
    println(intArrayOf(1, 2, 3).sumOf { it.toLong() * 3L })
    println(longArrayOf(1L, 2L).sumOf { it * 10 })
    println(floatArrayOf(1.5f, 2.5f).sumOf { it.toDouble() })
    println(doubleArrayOf(1.5, 2.5).sumOf { it * 2.0 })
    println(doubleArrayOf(1.5, 2.5).sumOf { 1 })

    // sumOf inside a nested lambda (mapIndexed) keeps resolving per receiver type
    val grid = arrayOf(intArrayOf(1, 0), intArrayOf(1, 1))
    println(grid.mapIndexed { y, row -> row.sumOf { v -> if (v > 0) grid.size - y else 0 } }.sum())
    val dgrid = arrayOf(doubleArrayOf(1.0, 0.0), doubleArrayOf(1.0, 1.0))
    println(dgrid.mapIndexed { y, row -> row.sumOf { v -> if (v > 0.0) (dgrid.size - y).toDouble() else 0.0 } }.sum())

    // lastIndex
    println(booleanArrayOf(true, false).lastIndex)
    println(shortArrayOf(1, 2, 3).lastIndex)
    println(floatArrayOf(1f).lastIndex)
    println(doubleArrayOf(1.0, 2.0).lastIndex)

}
