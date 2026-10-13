// KUU-2028: preserve the resolved Point-indexed Array.set extension.
data class Point(val x: Int, val y: Int)
operator fun Array<CharArray>.set(at: Point, c: Char) {
    this[at.y][at.x] = c
}
fun main() {
    val grid = arrayOf(charArrayOf('O'))
    grid[Point(0, 0)] = '.'
    println(grid[0][0])
}
