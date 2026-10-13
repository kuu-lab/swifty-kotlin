// SPDX-License-Identifier: Apache-2.0
// License: licenses/advent-2023-kotlin-LICENSE.txt
// KUU-1912: countSteps is copied unchanged from Todd Ginsberg's Day21.kt.
// Copyright (c) 2023 by Todd Ginsberg.
// https://github.com/tginsberg/advent-2023-kotlin/blob/0d5732508025a7e340366594c879b99fe6e7cbf0/src/main/kotlin/com/ginsberg/advent2023/Day21.kt
// Inject the known start to isolate KUU-1891; print distances to isolate KUU-1926.
data class Point2D(val x: Int, val y: Int) {
    fun cardinalNeighbors(): Set<Point2D> = setOf(
        Point2D(x, y - 1), Point2D(x + 1, y), Point2D(x, y + 1), Point2D(x - 1, y)
    )
}
fun Array<CharArray>.isSafe(at: Point2D) =
    at.y in this.indices && at.x in this[at.y].indices
operator fun Array<CharArray>.get(at: Point2D): Char = this[at.y][at.x]
class Garden(input: List<String>, private val start: Point2D) {
    private val gardenMap: Array<CharArray> = input.map { it.toCharArray() }.toTypedArray()
    fun distances(max: Int): List<Int> = countSteps(max).values.sorted()
    private fun countSteps(max: Int = gardenMap.size): Map<Point2D, Int> = buildMap {
        val queue = ArrayDeque<Pair<Point2D, Int>>().apply {
            add(start to 0)
        }
        while (queue.isNotEmpty()) {
            queue.removeFirst().let { (location, distance) ->
                if (location !in this && distance <= max) {
                    this[location] = distance
                    queue.addAll(
                        location
                            .cardinalNeighbors()
                            .filter { it !in this }
                            .filter { gardenMap.isSafe(it) }
                            .filter { gardenMap[it] != '#' }
                            .map { it to distance + 1 }
                    )
                }
            }
        }
    }
}
fun main() {
    val input = listOf(
        "...........", ".....###.#.", ".###.##..#.", "..#.#...#..", "....#.#....",
        ".##..S####.", ".##..#...#.", ".......##..", ".##.#.####.", ".##..##.##.", "..........."
    )
    val garden = Garden(input, Point2D(5, 5))
    println(garden.distances(-1))
    println(garden.distances(0))
    println(garden.distances(2))
    println(garden.distances(6))
    println(garden.distances(10))
}
