fun main() {
    var selectorCalls = 0
    val offset = 10
    val source = listOf(3, 1, 4, 2, 5).asSequence()
    val grouping = source.groupingBy {
        selectorCalls += 1
        it % 2 + offset
    }

    println(selectorCalls)
    println(grouping.sourceIterator().next())
    println(selectorCalls)
    println(grouping.keyOf(7))
    println(selectorCalls)

    println(grouping.eachCount())
    println(grouping.fold(0) { accumulator, element -> accumulator + element })
    println(grouping.reduce { _, accumulator, element -> accumulator + element })
    println(
        grouping.aggregate { key, accumulator: Int?, element, first ->
            if (first) element + key else accumulator!! + element
        }
    )
    println(selectorCalls)
}
