enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    val boxed: Any = Direction.WEST
    println(boxed is Enum<*>)
    println(boxed is Comparable<*>)
    println(Direction.NORTH.name)
    println(Direction.NORTH.ordinal)
    println(Direction.values().size)
    println(Direction.NORTH.compareTo(Direction.SOUTH))
    val values = enumValues<Direction>()
    println(values.size)
    println(values[0])
    println(enumValueOf<Direction>("SOUTH"))
    println(enumValueOf<Direction>("WEST"))
}
