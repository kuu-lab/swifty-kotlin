// KUU-2028: operator dispatch, canonical writes, and operand evaluation order.
data class Point(val x: Int, val y: Int)
operator fun Array<CharArray>.get(at: Point): Char = this[at.y][at.x]
operator fun Array<CharArray>.set(at: Point, c: Char) {
    this[at.y][at.x] = c
}
operator fun Array<CharArray>.set(x: Int, y: Int, c: Char) {
    println("set:$x,$y,$c")
    this[y][x] = c
}
operator fun IntArray.set(at: Point, value: Int) { this[at.x] = value }
operator fun IntArray.set(at: Long, value: Int) { this[at.toInt()] = value }
operator fun IntArray.set(x: Int, y: Int, value: Int) { this[x + y] = value }
fun Array<CharArray>.swap(a: Point, b: Point) {
    val tmp = this[a]
    this[a] = this[b]
    this[b] = tmp
}

fun receiver(grid: Array<CharArray>): Array<CharArray> {
    println("receiver")
    return grid
}
fun index(name: String): Int {
    println(name)
    return 0
}
fun value(): Char {
    println("value")
    return 'X'
}
fun assignErased(array: Array<*>) {
    val erased = array as Array<Any?>
    erased[0] = 42
}

fun main() {
    val grid = arrayOf(charArrayOf('O'))
    println(grid[Point(0, 0)])
    grid.set(Point(0, 0), '.')
    println(grid[Point(0, 0)])
    receiver(grid)[index("x"), index("y")] = value()
    println(grid[0][0])
    val swapGrid = arrayOf(charArrayOf('O', '.'))
    swapGrid.swap(Point(0, 0), Point(1, 0))
    println(swapGrid[0][0])
    println(swapGrid[0][1])

    val cells = arrayOf(charArrayOf('a', 'b'), charArrayOf('c', 'd'))
    var i = 0
    cells[i, i++] = 'Q'
    var j = 0
    cells[j, j] = ('R'.code + j++).toChar()
    println(cells[0][0])

    println(cells[0][1])
    println(cells[1][0])

    var current = grid
    current[0, 0] = run { current = cells; 'S' }
    println(grid[0][0])
    println(cells[0][0])

    current = grid
    current[run { current = cells; 0 }, 0] = 'T'
    println(grid[0][0])
    println(cells[0][0])

    val ints = intArrayOf(1, 2)
    ints[Point(0, 0)] = 7
    ints[1L] = 8
    ints[0, 0] = 6
    val intIndex: Int = 0
    ints[intIndex] = 9
    println(ints.toList())
    val boxed = arrayOf(1, 2)
    boxed[1] = 3
    assignErased(boxed)
    println(boxed.toList())
}
