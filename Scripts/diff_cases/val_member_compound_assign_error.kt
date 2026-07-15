// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
class Box(val n: Int)

fun main() {
    val b = Box(1)
    b.n += 5
    println(b.n)
}
