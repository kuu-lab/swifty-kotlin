fun isEven(value: Int): Boolean = value % 2 == 0

fun countWithEarlyReturn(values: Collection<Int>): Int {
    return values.count {
        if (it == 1) return 42
        it % 2 == 0
    }
}

fun main() {
    val values: Collection<Int> = listOf(0, 1, 2)
    println(values.count())
    println(values.count(::isEven))
    println(values.count(predicate = { it > 0 }))
    val lower = 0
    val upper = 2
    var visits = 0
    println(values.count {
        visits++
        it >= lower && it <= upper
    })
    println(visits)
    val predicate: (Int) -> Boolean = { it == 1 }
    println(values.count(predicate))
    val empty: Collection<Int> = emptyList<Int>()
    println(empty.count { true })
    val nullableElements: Collection<Int?> = listOf(null, 1, null)
    println(nullableElements.count { it == null })
    val mutable: MutableCollection<Int> = mutableListOf(0, 1, 2)
    println(mutable.count { it % 2 == 0 })
    val setCollection: Collection<Int> = setOf(0, 1, 2)
    println(setCollection.count { it % 2 == 0 })
    println(mapOf("a" to 0, "b" to 1, "c" to 2).values.count { it % 2 == 0 })
    val nullable: Collection<Int>? = values
    println(nullable?.count { it % 2 == 0 })
    val absent: Collection<Int>? = null
    println(absent?.count { it % 2 == 0 })
    val iterable: Iterable<Int> = Iterable { listOf(0, 1, 2).iterator() }
    println(iterable.count { it % 2 == 0 })
    println(countWithEarlyReturn(values))
    println(listOf(0, 1, 2).count { it % 2 == 0 })
    println(setOf(0, 1, 2).count { it % 2 == 0 })
    println(mapOf("a" to 0, "b" to 1, "c" to 2).count { it.value % 2 == 0 })
    println(sequenceOf(0, 1, 2).count { it % 2 == 0 })
}
