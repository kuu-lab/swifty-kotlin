package com.ginsberg.advent2023
operator fun Array<CharArray>.get(at: Point2D): Char = this[at.y][at.x]
fun Array<CharArray>.isSafe(at: Point2D): Boolean = at.y in this.indices && at.x in this[at.y].indices
class Grid(input: List<String>) {
    private val grid: Array<CharArray> = input.map { it.toCharArray() }.toTypedArray()
    private val progressions: Map<Point2D, List<Point2D>> = mapOf(
        Point2D.NORTH to grid.indices.flatMap { y ->
            grid.first().indices.map { x -> Point2D(x, y) }
        },
        Point2D.WEST to grid.first().indices.flatMap { x ->
            grid.indices.map { y -> Point2D(x, y) }
        },
        Point2D.SOUTH to grid.indices.reversed().flatMap { y ->
            grid.first().indices.map { x -> Point2D(x, y) }
        },
        Point2D.EAST to grid.first().indices.reversed().flatMap { x ->
            grid.indices.map { y -> Point2D(x, y) }
        }
    )
    private fun Array<CharArray>.tilt(direction: Point2D) {
        progressions.getValue(direction).filter { this[it] == 'O' }.forEach { doTilt(it, direction) }
    }
    private fun Array<CharArray>.doTilt(place: Point2D, direction: Point2D) {
        var current = place
        while (isSafe(current + direction) && this[current + direction] == '.') {
            current += direction
        }
    }
    fun run() { grid.tilt(Point2D.NORTH); println("done") }
}
fun main() { Grid(listOf("O.", ".O")).run() }
