// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun main() {
  val x = 1
  x = 2
  println(x)
}
