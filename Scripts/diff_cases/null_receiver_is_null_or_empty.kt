// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun main() {
    val s: String? = null
    println(s.isNullOrEmpty())
    println(null.isNullOrEmpty())
    println("".isNullOrEmpty())
    println("hi".isNullOrEmpty())
}
