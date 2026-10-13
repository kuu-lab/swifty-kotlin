// KUU-2001: Inapplicable members must not hide operator get extensions.
// KOTLINC_FLAGS: -Xjdk-release=17
data class Point(val x: Int, val y: Int)
data class ConcretePoint(val x: Int, val y: Int)
data class Vertex<T>(val value: T)

operator fun <T> List<List<T>>.get(at: Point): T = this[at.y][at.x]
operator fun List<List<Int>>.get(at: ConcretePoint): Int = this[at.y][at.x]
fun <T> List<List<T>>.at(at: Point): T = this[at.y][at.x]

class Slots {
    operator fun get(index: Int): Int = index + 10
}
operator fun Slots.get(index: Int): Int = index + 100
operator fun Slots.get(index: String): Int = index.length + 20
operator fun Slots.get(x: Int, y: Int): Int = x + y + 30

class LiteralSlots {
    operator fun get(index: String): Long = 0L
}
operator fun LiteralSlots.get(index: Long): Long = index + 40L

class NullableLiteralSlots {
    operator fun get(index: String): Boolean = false
}
operator fun NullableLiteralSlots.get(index: Long?): Boolean = index != null

fun <T> lookup(vertices: Map<Vertex<T>, Int>, key: Vertex<T>?): Int? = vertices[key]

fun main() {
    val relations = mapOf('(' to ')')
    val missing: Char? = null
    val present: Char? = '('
    println(relations[missing])
    println(relations[present])
    println(relations['('])
    println(relations.get(missing))
    val mutable = mutableMapOf('(' to ')')
    println(mutable[missing])
    println(mutable[present])
    val vertices = mapOf(Vertex(1) to 42)
    println(lookup(vertices, null))
    println(lookup(vertices, Vertex(1)))
    val grid = listOf(listOf(7))
    println(2 + grid[Point(0, 0)])
    println(2 + grid.get(Point(0, 0)))
    println(2 + grid.at(Point(0, 0)))
    println(2 + grid[ConcretePoint(0, 0)])
    println(2 + grid.get(ConcretePoint(0, 0)))
    println(grid[0][0])
    val slots = Slots()
    println(slots[1])
    println(slots["abc"])
    println(slots[1, 2])
    println(LiteralSlots()[1])
    println(NullableLiteralSlots()[0])
}
