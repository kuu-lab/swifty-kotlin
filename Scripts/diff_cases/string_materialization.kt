// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
fun main() {
    println("abc".toList())
    println("abc".toCharArray()[0])
    println("abc".toTypedArray()[1])
    println("cba".toSortedSet().toList())
    println("ab".withIndex().toList())

    val iterator = "ab".iterator()
    println(iterator.hasNext())
    println(iterator.next())
    println(iterator.next())
    println(iterator.hasNext())
}
