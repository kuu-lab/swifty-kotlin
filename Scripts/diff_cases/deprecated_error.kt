// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
@Deprecated("Use replacement", level = DeprecationLevel.ERROR)
fun oldApi(): Int = 1

fun main() {
    oldApi()
}
