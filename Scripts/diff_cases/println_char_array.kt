fun main() {
    val r = CharArray(10) { 'x' }
    r[3] = '#'
    println(r)
    print(r)
    println()
    val grid = arrayOf(charArrayOf('a', 'b'), charArrayOf('.', 'S'))
    for (row in grid) println(row)
    println(charArrayOf())
}
