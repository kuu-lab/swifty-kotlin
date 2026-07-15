// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun main() {
    println("%2$s:%1$d".format(7, "age"))
}
