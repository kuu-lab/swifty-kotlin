// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
enum class Color { RED, GREEN, BLUE }

fun main() {
    val entries = enumEntries<Color>()
    println(entries)
    println(entries.size)
}
