fun main() {
    val words = listOf("apple", "banana", "avocado", "blueberry", "cherry")
    val grouping = words.groupingBy { it.substring(0, 1) }

    println(grouping.eachCount())
    println(grouping.eachCountTo(mutableMapOf("z" to 10)))

    println(grouping.fold(0) { accumulator, element -> accumulator + element.length })
    println(
        grouping.fold(
            { key, element -> key.length + element.length },
            { key, accumulator, element -> accumulator + key.length + element.length }
        )
    )
    println(grouping.foldTo(mutableMapOf("z" to 100), 0) { accumulator, element -> accumulator + element.length })

    println(grouping.reduce { key, accumulator, element -> if (element.length > accumulator.length) element else accumulator })
    println(grouping.reduceTo(mutableMapOf("z" to "zebra")) { key, accumulator, element -> accumulator + "/" + element })

    println(
        grouping.aggregate { key, accumulator: Int?, element, first ->
            if (first) element.length else accumulator!! + element.length
        }
    )
    println(
        grouping.aggregateTo(mutableMapOf("z" to 1)) { key, accumulator: Int?, element, first ->
            if (accumulator == null) element.length else accumulator + element.length
        }
    )

    val setGrouping = setOf(1, 2, 3, 4, 5, 6).groupingBy { it % 3 }
    println(setGrouping.eachCount())
    println(setGrouping.reduce { key, accumulator, element -> accumulator + element })
}
