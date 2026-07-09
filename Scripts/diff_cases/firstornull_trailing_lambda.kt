// SKIP-DIFF (DEBT-DIFF-007): firstOrNull { predicate } trailing-lambda call resolves to the
// no-arg firstOrNull() overload instead of the predicate overload, so the predicate is never
// evaluated and the first element is always returned regardless of the condition.
fun main() {
    println(listOf(1, 2, 3).firstOrNull { it > 2 })
}
