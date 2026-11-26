// DIFF_JVM
fun main() {
    val words = listOf("apple", "banana", "avocado", "blueberry", "cherry")
    val grouping = words.groupingBy { it.substring(0, 1) }

    println(
        grouping.aggregate { key, accumulator: Int?, element, first ->
            if (first) element.length else accumulator!! + element.length
        }
    )

    val destination = mutableMapOf("z" to 1, "a" to 100)
    val returned = grouping.aggregateTo(destination) { key, accumulator: Int?, element, first ->
        if (accumulator == null) element.length else accumulator + element.length
    }
    println(returned)
    println(returned === destination)

    val linked = linkedMapOf("a" to 1)
    println(grouping.aggregateTo(linked) { _, n: Int?, element, _ -> (n ?: 0) + element.length } === linked)
    println(linked)
    println(grouping.eachCount())

    val firsts = mutableListOf<String>()
    val joined = grouping.aggregate { key, accumulator: String?, element, first ->
        if (first) firsts.add(key)
        if (accumulator == null) element else "$accumulator+$element"
    }
    println(joined)
    println(firsts)

    println(emptyList<String>().groupingBy { it }.aggregate { _, acc: Int?, e, _ -> (acc ?: 0) + e.length })

    val setGrouping = setOf(1, 2, 3, 4, 5, 6).groupingBy { it % 3 }
    println(setGrouping.aggregate { _, accumulator: Int?, element, first -> if (first) element else accumulator!! * element })
}
