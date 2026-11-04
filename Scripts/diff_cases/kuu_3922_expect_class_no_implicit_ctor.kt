// DIFF_CANDIDATE_ONLY
// KUU-3922: an `expect class` without `()` declares no constructor at all
// (kotlinc MPP rule), so a same-named top-level function does not collide
// with an implicit no-arg ctor — kotlinx-datetime's `expect class UtcOffset`
// + deprecated `fun UtcOffset()`. Calls bind the function, which forwards
// to the companion's ZERO.
package diff.kmp

expect class UtcOffset {
    val totalSeconds: Int
    companion object {
        val ZERO: UtcOffset
    }
}

actual class UtcOffset private actual constructor(actual val totalSeconds: Int) {
    actual companion object {
        actual val ZERO: UtcOffset = UtcOffset(totalSeconds = 0)
    }
}

fun UtcOffset(): UtcOffset = UtcOffset.ZERO

fun main() {
    println(UtcOffset().totalSeconds)
}
