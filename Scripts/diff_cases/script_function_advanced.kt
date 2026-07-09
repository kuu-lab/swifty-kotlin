// SKIP-DIFF (DEBT-DIFF-002): not a timeout — kswiftc only synthesizes an implicit `main` when a
// file has top-level statements AND no other top-level declarations (KotlinParser.parseFile
// scriptKind rule); the top-level `fun`s below disqualify script treatment, so linking fails
// with KSWIFTK-LINK-0002 (no `main`). This case would ALSO fail once script mode is supported:
// its logic independently hits two more bugs, isolated as their own minimal repros (see
// docs/diff-skip-inventory.md for the tracked debt IDs):
//   - firstornull_trailing_lambda.kt: `firstOrNull { predicate }` resolves to the no-arg
//     overload, so the predicate is never evaluated.
//   - vararg_any_boolean_element.kt: a Boolean pulled out of a `vararg items: Any` array
//     prints as "1" instead of "true".
fun<T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    for (item in this) {
        if (predicate(item)) return item
    }
    return null
}

fun printAll(vararg items: Any) {
    items.forEach { println(it) }
}

fun calculate(base: Int, multiplier: Int = 2): Int = base * multiplier

println(listOf(1, 2, 3).firstOrNull { it > 2 })
printAll("Hello", 42, true)
println(calculate(10))
println(calculate(10, 3))
