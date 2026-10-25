fun main() {
    val values = listOf(10, 20, 30)
    val iterable: Iterable<Int> = values
    val set: Iterable<Int> = setOf(4, 5, 6)

    println(values.elementAt(1))
    println(iterable.elementAt(2))
    println(set.elementAt(1))
    println(values.elementAtOrNull(3) ?: -1)
    println(set.elementAtOrNull(-1) ?: -1)
    println(values.elementAtOrElse(1) { it * 100 })
    println(set.elementAtOrElse(8) { it * 100 })
    println(set.elementAtOrElse(-2) { it * 100 })
    try {
        values.elementAt(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("list-index-error")
    }
    try {
        set.elementAt(8)
    } catch (e: IndexOutOfBoundsException) {
        println("iterable-index-error")
    }

    val oneList = listOf(7)
    val oneIterable: Iterable<Int> = setOf(9)
    println(oneList.single())
    println(oneIterable.single())
    println(oneList.singleOrNull())
    println(oneIterable.singleOrNull())
    println(values.single { it == 20 })
    println(set.single { it == 5 })
    println(values.singleOrNull { it == 20 })
    println(set.singleOrNull { it == 5 })
    println(values.singleOrNull { it > 0 })
    println(set.singleOrNull { it > 0 })
    println(emptyList<Int>().singleOrNull())
    println(emptySet<Int>().singleOrNull())
    try {
        emptyList<Int>().single()
    } catch (e: NoSuchElementException) {
        println("empty-single-error")
    }
    try {
        set.single()
    } catch (e: IllegalArgumentException) {
        println("multiple-single-error")
    }
    try {
        values.single { it < 0 }
    } catch (e: NoSuchElementException) {
        println("no-match-single-error")
    }
    try {
        set.single { it > 0 }
    } catch (e: IllegalArgumentException) {
        println("multiple-match-single-error")
    }

    val nullable: Iterable<Int?> = listOf<Int?>(null)
    println(nullable.singleOrNull() == null)
    println(nullable.singleOrNull { it == null } == null)
}
