fun main() {
    // reduce on a Set receiver widened to Iterable<Int>: must dispatch through
    // the Set's own itable, not Sequence<T>.reduce (which crashed at runtime
    // with "Virtual dispatch failed").
    val iterableFromSet: Iterable<Int> = setOf(2, 3, 4)
    println(iterableFromSet.reduce { acc, v -> acc * v })

    val iterableFromList: Iterable<Int> = listOf(5, 6, 7)
    println(iterableFromList.reduce { acc, v -> acc + v })

    println(setOf(1, 2, 3).reduce { acc, v -> acc + v })

    val iterableForReduceIndexed: Iterable<Int> = setOf(10, 20, 30)
    println(iterableForReduceIndexed.reduceIndexed { idx, acc, v -> acc + v + idx })

    // fold/scan have no dedicated Iterable synthetic stub, so they must fall
    // back to the bundled Sequence<T> source body instead of crashing with an
    // unresolved kk_list_fold/kk_list_scan linker error.
    val iterableForFold: Iterable<Int> = setOf(1, 2, 3)
    println(iterableForFold.fold(0) { acc, v -> acc + v })

    val iterableFoldFromList: Iterable<Int> = listOf(1, 2, 3, 4)
    println(iterableFoldFromList.fold(1) { acc, v -> acc * v })

    val iterableForScan: Iterable<Int> = setOf(1, 2, 3)
    println(iterableForScan.scan(0) { acc, v -> acc + v })

    // Sanity: an actual Sequence receiver must still resolve to Sequence.reduce.
    val seq = generateSequence(1) { if (it < 5) it + 1 else null }
    println(seq.reduce { acc, v -> acc + v })
    println(listOf(1, 2, 3, 4).asSequence().reduce { acc, v -> acc + v })

    // Sanity: map/filter must still work on an Iterable<Int> receiver.
    val iterableForFilter: Iterable<Int> = setOf(1, 2, 3, 4, 5)
    println(iterableForFilter.filter { it % 2 == 0 })
}
