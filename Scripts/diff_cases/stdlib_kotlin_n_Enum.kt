enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    val boxed: Any = Direction.WEST
    println(boxed is Enum<*>)
    println(boxed is Comparable<*>)
    println(Direction.NORTH.name)
    println(Direction.NORTH.ordinal)
    println(Direction.values().size)
    println(Direction.NORTH.compareTo(Direction.SOUTH))
}
