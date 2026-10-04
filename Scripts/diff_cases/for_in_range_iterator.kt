// KSP-452: for-in over a range goes through the bundled `iterator()` operator
// (kotlin.ranges.RangeIterators) instead of a range-specific lowering, so the
// direct form and the same range held in a typed value must agree.
fun main() {
    for (i in 1..5) print("$i ")
    println()
    for (i in 5 downTo 1) print("$i ")
    println()
    for (i in 1 until 5) print("$i ")
    println()
    for (i in 1..10 step 3) print("$i ")
    println()
    for (i in 10 downTo 1 step 4) print("$i ")
    println()
    for (i in 1..0) print("unreachable $i")
    println("empty")
    for (i in 1 downTo 2) print("unreachable $i")
    println("empty-desc")

    val intRange: IntRange = 1..4
    for (i in intRange) print("$i ")
    println()
    val progression: IntProgression = 1..9 step 4
    for (i in progression) print("$i ")
    println()

    for (l in 1L..4L) print("$l ")
    println()
    for (l in 4L downTo 1L step 2L) print("$l ")
    println()
    val longRange: LongRange = 2L..5L
    for (l in longRange) print("$l ")
    println()

    for (c in 'a'..'e') print("$c ")
    println()
    for (c in 'e' downTo 'a' step 2) print("$c ")
    println()
    val charRange: CharRange = 'x'..'z'
    for (c in charRange) print("$c ")
    println()

    var total = 0
    outer@ for (i in 1..5) {
        for (j in 1..5) {
            if (j > i) continue@outer
            if (i == 5) break@outer
            total += j
        }
    }
    println(total)

    var nested = 0
    for (i in 1..3) {
        for (j in 1..3) {
            nested += i * j
        }
    }
    println(nested)

    val iterator = (1..3).iterator()
    while (iterator.hasNext()) print("${iterator.next()} ")
    println()

    // Bounds that are not compile-time constants: an empty `until` must stay
    // empty (the runtime marks it with step 0, not with crossing bounds).
    println(sumUntil(0))
    println(sumUntil(4))
    println(sumDownTo(0))
    println(sumLongUntil(0L))
    println(sumLongUntil(3L))
}

fun sumUntil(bound: Int): Int {
    var sum = 0
    for (i in 0 until bound) sum += i + 1
    return sum
}

fun sumDownTo(bound: Int): Int {
    var sum = 0
    for (i in 0 downTo bound) sum += i + 1
    return sum
}

fun sumLongUntil(bound: Long): Long {
    var sum = 0L
    for (l in 0L until bound) sum += l + 1L
    return sum
}
