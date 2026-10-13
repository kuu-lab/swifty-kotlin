// KUU-1892: LongRange.forEach returns leave the enclosing function.
fun find(): Long {
    (1L..3L).forEach { n -> if (n == 2L) return n }
    return -1L
}

fun nestedFind(): Long {
    val range = 1L..3L
    while (true) {
        range.forEach { x ->
            range.forEach { y ->
                if (x == 2L && y == 2L) {
                    range.forEach { z ->
                        if (z == 2L) return x * 100L + y * 10L + z
                    }
                }
            }
        }
    }
}

fun normalCompletion(): Long {
    var total = 0L
    (1L..3L).forEach { total += it }
    return total
}

fun main() {
    println(find())
    println(nestedFind())
    println(normalCompletion())
}
