// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
typealias A = B
typealias B = A

fun main() {
    println(0)
}
