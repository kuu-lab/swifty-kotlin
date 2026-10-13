// KUU-1889: preserve the Day10 maze reproducer and Array.indexOfFirst boundaries.
fun main() {
    val maze=arrayOf(charArrayOf('S','.'));println(maze.indexOfFirst { 'S' in it })

    val emptyCalls = intArrayOf(0)
    val emptyIndex = emptyArray<Int>().indexOfFirst { emptyCalls[0]++; true }
    println(emptyIndex)
    println(emptyCalls[0])

    val noMatchCalls = intArrayOf(0)
    val noMatchIndex = arrayOf(1, 2, 3).indexOfFirst { noMatchCalls[0]++; it == 4 }
    println(noMatchIndex)
    println(noMatchCalls[0])

    val firstCalls = intArrayOf(0)
    val firstIndex = arrayOf(4, 5, 6).indexOfFirst { firstCalls[0]++; it == 4 }
    println(firstIndex)
    println(firstCalls[0])

    val middleCalls = intArrayOf(0)
    val middleIndex = arrayOf(4, 5, 6).indexOfFirst { middleCalls[0]++; it == 5 }
    println(middleIndex)
    println(middleCalls[0])

    val lastCalls = intArrayOf(0)
    val lastIndex = arrayOf(4, 5, 6).indexOfFirst { lastCalls[0]++; it == 6 }
    println(lastIndex)
    println(lastCalls[0])

    val covariant: Array<out String> = arrayOf("a", "b")
    println(covariant.indexOfFirst { it == "b" })
}
