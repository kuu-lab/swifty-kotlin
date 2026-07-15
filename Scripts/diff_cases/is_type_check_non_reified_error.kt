// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun <T> isOf(v: Any): Boolean = v is T

fun main() {
    println(isOf<Int>(1))
}
