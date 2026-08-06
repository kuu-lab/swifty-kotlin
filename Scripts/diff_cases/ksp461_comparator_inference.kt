data class Person(val name: String, val age: Int)

fun main() {
    val people = listOf(Person("cid", 30), Person("amy", 25), Person("bob", 25))

    // Multi-selector compareBy without explicit type arguments.
    val byAgeThenName = compareBy({ p: Person -> p.age }, { p: Person -> p.name })
    println(people.sortedWith(byAgeThenName).map { it.name })

    // Implicit `it` selectors.
    println(listOf("banana", "fig", "apple").sortedWith(compareBy<String>({ it.length }, { it })))
    println(listOf(3, 1, 2).sortedWith(compareBy<Int> { it }.reversed()))

    // compareValues / compareValuesBy with an inferred implicit `it` selector.
    println(compareValues(1, 2))
    println(compareValuesBy(13, 25) { it % 10 })
    println(compareValuesBy(13, 25, compareBy<Int> { it }) { it % 10 })

    // Null ordering wrappers.
    val values = listOf(3, null, 25, null, 14)
    println(values.sortedWith(nullsFirst(compareBy { it })))
    println(values.sortedWith(nullsLast(compareBy { it })))

    // maxOf / minOf with a comparator.
    val byLength = compareBy<String> { it.length }
    println(maxOf("aa", "b", byLength))
    println(minOf("aa", "b", "cccc", byLength))
}
