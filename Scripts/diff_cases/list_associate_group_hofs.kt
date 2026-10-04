fun main() {
    val values = listOf("a", "bb", "ccc", "dd")

    println(values.associate { it to it.length })
    println(values.associateBy { it.length })
    println(values.associateBy({ it.length }, { it.uppercase() }))
    println(values.associateWith { it.length })

    val associateToDestination = mutableMapOf<String, Int>()
    println(values.associateTo(associateToDestination) { it to it.length })

    val associateByToDestination = mutableMapOf<Int, String>()
    println(values.associateByTo(associateByToDestination) { it.length })

    val associateByToTransformedDestination = mutableMapOf<Int, Int>()
    println(values.associateByTo(associateByToTransformedDestination, { it.length }, { it.length * 2 }))

    val associateWithToDestination = mutableMapOf<String, Int>()
    println(values.associateWithTo(associateWithToDestination) { it.length })

    println(values.groupBy { it.length })
    println(values.groupBy({ it.length }, { it.uppercase() }))

    val groupByToDestination = mutableMapOf<Int, MutableList<String>>()
    println(values.groupByTo(groupByToDestination) { it.length })

    val groupByToTransformedDestination = mutableMapOf<Int, MutableList<Int>>()
    println(values.groupByTo(groupByToTransformedDestination, { it.length }, { it.length * 2 }))

    val seen = mutableListOf<String>()
    val indexedSeen = mutableListOf<String>()
    val onEachResult = values.onEach { seen.add(it) }
    val onEachIndexedResult = values.onEachIndexed { index, value -> indexedSeen.add("$index:$value") }
    println(onEachResult)
    println(seen)
    println(onEachIndexedResult)
    println(indexedSeen)

    println(values.partition { it.length % 2 == 0 })
    println(values.zip(listOf(1, 2, 3, 4)).unzip())
}
