// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun main() {
    println(buildString(1))
    println(buildList(1))
    println(buildMap(1))
}
