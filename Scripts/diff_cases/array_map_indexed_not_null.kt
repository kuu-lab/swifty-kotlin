// KUU-1891: object Array keeps original indices while discarding null results.

private class Start(val x: Int, val y: Int) {
    override fun toString(): String = "$x:$y"
}

private fun nonLocalReturn(): Int {
    arrayOf("skip", "hit").mapIndexedNotNull { index, value ->
        if (value == "hit") return index
        null
    }
    return -1
}

fun Array<Int>.mapIndexedNotNull(value: String): String = value

fun main() {
    println(arrayOf(charArrayOf('.'),charArrayOf('S')).mapIndexedNotNull { y,row -> if('S' in row)y else null })

    val rows = arrayOf(charArrayOf('.'), charArrayOf('S'), charArrayOf('.'), charArrayOf('S'))
    val starts: List<Start> = rows.mapIndexedNotNull { y, row ->
        if ('S' in row) Start(row.indexOf('S'), y) else null
    }
    println(starts)

    val visits = mutableListOf<String>()
    val projected: Array<out String?> = arrayOf(null, "a", null, "bb")
    val words: List<String> = projected.mapIndexedNotNull { index, value ->
        visits.add("$index:$value")
        if (value != null) "$index:$value" else null
    }
    println(words)
    println(visits)

    val flags: List<Boolean> = arrayOf(0, 1, 2).mapIndexedNotNull { index, value ->
        if (index != 1) value == 2 else null
    }
    println(flags)
    println(arrayOf(0, 10, 20).mapIndexedNotNull { index, value -> if (index != 1) value else null })

    val allNull: List<Int> = arrayOf("a", "b").mapIndexedNotNull { _, _ -> null }
    println(allNull)
    var emptyCalls = 0
    val empty: List<String> = emptyArray<Int>().mapIndexedNotNull { _, _ ->
        emptyCalls++
        "unexpected"
    }
    println(empty)
    println(emptyCalls)

    val live = arrayOf(1, 2, 3)
    println(live.mapIndexedNotNull { index, value ->
        if (index == 0) live[1] = 9
        if (index == 2) null else value
    })
    val callback: (Int, Int) -> String? = { index, value ->
        if (value % 2 == 0) "$index:$value" else null
    }
    println(arrayOf(1, 2, 3, 4).mapIndexedNotNull(transform = callback))
    println(arrayOf(1).mapIndexedNotNull("user"))
    println(nonLocalReturn())

    var throwingVisits = 0
    try {
        arrayOf(1, 2, 3).mapIndexedNotNull { index, value ->
            throwingVisits++
            if (index == 1) throw IllegalStateException("stop")
            value
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println(throwingVisits)

    println(listOf(1, 2).mapIndexedNotNull { index, value -> if (index == 0) null else value })
    println("ab".mapIndexedNotNull { index, value -> if (index == 0) null else value })
    println(sequenceOf(1, 2).mapIndexedNotNull { index, value -> if (index == 0) null else value }.toList())
}
