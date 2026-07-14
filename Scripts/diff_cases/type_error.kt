// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun needInt(v: Int) = v

fun main() {
    println(needInt("oops"))
}
