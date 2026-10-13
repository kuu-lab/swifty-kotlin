// KUU-2002: CharArray Int selectors and the original Day14 score shape.
// KOTLINC_FLAGS: -Xjdk-release=17
class CharArraySumOfGrid {
    private fun Array<CharArray>.score(): Int =
        mapIndexed { y, row ->
            row.sumOf { c -> if (c == 'O') size - y else 0 }
        }.sum()

    private fun Array<CharArray>.explicitScore(): Int =
        this.mapIndexed { y, row ->
            row.sumOf { c -> if (c == 'O') size - y else 0 }
        }.sum()

    fun score(): Int = arrayOf(charArrayOf('O', '.'), charArrayOf('O', 'O')).score()
    fun explicitScore(): Int = arrayOf(charArrayOf('O', '.'), charArrayOf('O', 'O')).explicitScore()
}

fun main() {
    println(charArrayOf('O', '.', 'O').sumOf { c -> if (c == 'O') 2 else 0 })
    var calls = 0
    println(charArrayOf().sumOf { c -> calls++; c.code })
    println(calls)
    println(charArrayOf('a', 'b', 'c').sumOf { c -> -(c.code - 96) })

    val selector: (Char) -> Int = { c -> c.code }
    println(charArrayOf('A', 'Z').sumOf(selector))
    val visited = mutableListOf<Int>()
    println(charArrayOf('C', 'A', 'B').sumOf { c -> visited.add(c.code); 1 })
    println(visited.joinToString(","))
    println(charArrayOf('a', 'b').sumOf { c -> if (c == 'a') Int.MAX_VALUE else 1 })

    println(charArrayOf('\u0000', '\uD83D', '\uDE00', '\uFFFF').sumOf { it.code })

    // Existing overloads and the isolated outer mapIndexed control.
    println(charArrayOf('O', '.', 'O').toList().sumOf { c -> if (c == 'O') 2 else 0 })
    println(arrayOf('O', '.', 'O').sumOf { c -> if (c == 'O') 2 else 0 })
    val grid = arrayOf(charArrayOf('O', '.'), charArrayOf('O', 'O'))
    println(grid.mapIndexed { y, row -> row.size - y }.sum())
    println(grid.mapIndexed { y, row -> row.sumOf { c -> if (c == 'O') grid.size - y else 0 } }.sum())
    println(grid.mapIndexed { y: Int, row: CharArray -> row.sumOf { c: Char -> if (c == 'O') grid.size - y else 0 } }.sum())
    println(CharArraySumOfGrid().score())
    println(CharArraySumOfGrid().explicitScore())
}
