// CANDIDATE-ONLY: DEBT-DIFF-001; kotlinc lacks KSwiftK's bundled top-level two-value API.
import kotlin.comparisons.maxWith
import kotlin.comparisons.minWith
import kotlin.comparisons.naturalOrder
import kotlin.comparisons.reverseOrder

// KSP-684: top-level maxWith/minWith must dispatch through Comparator.compare.
fun main() {
    println(maxWith(naturalOrder<Int>(), 3, 7))
    println(minWith(naturalOrder<Int>(), 3, 7))
    println(maxWith(reverseOrder<Int>(), 3, 7))
    println(minWith(reverseOrder<Int>(), 3, 7))
    println(maxWith(naturalOrder<Int>(), 5, 5))
    println(minWith(naturalOrder<Int>(), 5, 5))
}
