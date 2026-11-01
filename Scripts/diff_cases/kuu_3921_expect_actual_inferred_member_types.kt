// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3921_expect_actual_inferred_member_types.expected.stdout
// Candidate-only: this single-file harness cannot model common/platform source sets for JVM kotlinc; compare the candidate's expect/actual runtime output directly.
// KUU-3921: actual members may omit their type annotation when inference pins
// the same type the expect side declares.
package diff.kmp

expect class LocalDate {
    companion object {
        val MIN: LocalDate
        val MAX: LocalDate
    }
}
expect val topX: Int
expect fun topF(): Int

actual class LocalDate {
    actual companion object {
        actual val MIN = LocalDate()
        actual val MAX = LocalDate()
    }
}
actual val topX = 20
actual fun topF() = 22

fun main() {
    println(LocalDate.MIN === LocalDate.MIN)
    println(LocalDate.MIN === LocalDate.MAX)
    println(topX + topF())
}
