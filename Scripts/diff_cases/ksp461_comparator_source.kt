// KSP-461: the whole Comparator / comparison surface is bundled Kotlin source.
data class Row(val group: Int, val score: Int, val name: String)

fun main() {
    val rows = listOf(
        Row(2, 10, "b"),
        Row(1, 20, "a"),
        Row(1, 20, "c"),
        Row(1, 10, "d")
    )

    // compareBy with 2 / 3 / vararg selectors.
    println(rows.sortedWith(compareBy<Row>({ it.group }, { it.score })).map { it.name })
    println(rows.sortedWith(compareBy<Row>({ it.group }, { it.score }, { it.name })).map { it.name })
    println(
        rows.sortedWith(
            compareBy<Row>({ it.group }, { it.score }, { it.name.length }, { it.name })
        ).map { it.name }
    )

    // Comparator.reversed and comparator-taking compareBy.
    println(rows.sortedWith(compareBy<Row> { it.score }.reversed()).map { it.name })
    println(rows.sortedWith(compareBy<Row, Int>(reverseOrder()) { it.score }).map { it.name })

    // compareValues / compareValuesBy overloads.
    println(compareValues(1, 2))
    println(compareValues(null, 1))
    println(compareValues(1, null))
    println(compareValues<Int>(null, null))
    println(compareValuesBy(rows[0], rows[1]) { r: Row -> r.group })
    println(compareValuesBy(rows[1], rows[2], { r: Row -> r.group }, { r: Row -> r.name }))
    println(compareValuesBy(rows[1], rows[2], { r: Row -> r.group }, { r: Row -> r.score }, { r: Row -> r.name }))
    println(
        compareValuesBy(
            rows[1],
            rows[2],
            { r: Row -> r.group },
            { r: Row -> r.score },
            { r: Row -> r.name },
            { r: Row -> r.name.length }
        )
    )
    println(compareValuesBy(rows[0], rows[1], reverseOrder<Int>()) { r: Row -> r.score })

    // String comparison keeps Kotlin's character-difference magnitude.
    println(compareValues("a", "c"))
    println(compareValuesBy(rows[1], rows[2]) { r: Row -> r.name })

    // nullsFirst / nullsLast, natural and comparator based.
    val values: List<Int?> = listOf(3, null, 1, null, 2)
    println(values.sortedWith(nullsFirst<Int>()))
    println(values.sortedWith(nullsLast<Int>()))
    println(values.sortedWith(nullsFirst(reverseOrder<Int>())))
    println(values.sortedWith(nullsLast(reverseOrder<Int>())))
    println(values.sortedWith(nullsFirst(compareBy<Int> { it })))
    println(values.sortedWith(nullsLast(compareBy<Int> { it })))

    // Primitive selectors keep their natural (unboxed) ordering.
    println(listOf(3L, 1L, 2L).sortedWith(compareBy<Long> { it }))
    println(listOf(1.5, 0.5, 2.5).sortedWith(compareByDescending<Double> { it }))
    println(listOf('c', 'a', 'b').sortedWith(compareBy<Char> { it }))

    // String.CASE_INSENSITIVE_ORDER keeps its singleton identity.
    val order = String.CASE_INSENSITIVE_ORDER
    println(listOf("Banana", "apple", "Cherry").sortedWith(order))
    println(order.compare("ABC", "abc"))
    println(order === String.CASE_INSENSITIVE_ORDER)
}
