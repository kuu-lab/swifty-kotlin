enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    val boxed: Any = Direction.WEST
    println(boxed is Direction)
    println(boxed is Enum<*>)
    println(boxed is Comparable<*>)
    println(boxed !is Direction)
    println(boxed as Direction)
    println(boxed as? Direction)
    println(Direction::class.isInstance(boxed))

    val other: Any = 42
    println(other is Direction)
    println(other as? Direction)
    println(Direction::class.isInstance(other))

    val mixed: List<Any> = listOf(Direction.NORTH, Direction.SOUTH)
    println(mixed.filterIsInstance<Direction>())
}
